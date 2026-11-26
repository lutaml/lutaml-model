# frozen_string_literal: true

module Lutaml
  module Formatter
    # The canonical LML emitter (RS 3001 informative "Canonical form"):
    # a deterministic rendering of the document model. Canonicality is a
    # formatting operation, not a validity constraint. The rules live in
    # TODO.next/sota/canon.md.
    #
    # Laws: format(format(x)) == format(x) (idempotence), and
    # parse(format(parse(x))) equals parse(x) under the document-model
    # comparison.
    class Canonical
      include Lutaml::Lml::Quoting

      GROUPS = %i[
        namespaces packages classes enums data_types primitives
        serialization_mappings associations diagrams
      ].freeze

      VISIBILITY_SYMBOLS = {
        'private' => '-', 'protected' => '#', 'package' => '~'
      }.freeze

      VISIBILITY_WORDS = %w[private protected package].freeze

      def initialize(document)
        @document = document
        @lines = []
        @level = 0
        @bodies = []
      end

      def render
        render_document(@document)
        trim_trailing_blanks
        return '' if @lines.empty?

        "#{@lines.join("\n")}\n"
      end

      private

      # ---- document ----

      def render_document(doc)
        unless doc.lml_version.to_s.empty?
          line("lml #{quote_always(doc.lml_version)}")
          blank_line
        end
        Array(doc.requires).each { |path| line("require #{quote_always(path)}") }
        blank_line if Array(doc.requires).any?

        Array(doc.comments).each { |comment| top { render_comment(comment) } }

        render_scope(doc)
        top { render_instance(doc.instance) } if doc.instance
        top { render_instance_collection(doc.instances) } if doc.instances
        render_views(doc)
      end

      def render_scope(doc)
        return render_model_members(doc) if doc.name.to_s.empty?

        top do
          render_block("models #{quote_scalar(doc.name)}#{version_suffix(doc)}") do
            render_model_members(doc)
          end
        end
      end

      def version_suffix(doc)
        version = doc.model_versions[doc.name]
        version.nil? ? '' : " version #{quote_always(version)}"
      end

      def render_model_members(doc)
        %i[title caption fontname].each do |attribute|
          value = doc.public_send(attribute)
          next if value.to_s.empty?

          top { line("#{attribute} #{quote_always(value)}") }
        end

        GROUPS.each do |collection|
          Array(doc.public_send(collection)).each do |item|
            top { render_group_member(collection, item) }
          end
        end
      end

      def render_group_member(collection, item)
        case collection
        when :namespaces then render_namespace(item)
        when :packages then render_package(item)
        when :classes then render_class(item)
        when :enums then render_enum(item)
        when :data_types then render_data_type(item)
        when :primitives then render_primitive(item)
        when :serialization_mappings then render_mapping(item)
        when :associations then render_association(item)
        when :diagrams then render_diagram(item)
        end
      end

      def render_views(doc)
        imports = Array(doc.view_imports)
        show = doc.show_filter
        hide = doc.hide_filter
        return if imports.empty? && show.nil? && hide.nil?

        top do
          render_block("view #{quote_scalar(doc.name)}") do
            imports.each { |entry| member { line("import #{quote_always(entry.path)}") } }
            member { line("show #{show.entity_names.join(', ')}") } if show
            member { line("hide #{hide.entity_names.join(', ')}") } if hide
          end
        end
      end

      # ---- declarations ----

      def render_namespace(namespace)
        render_block("namespace #{namespace.name}") do
          line("uri #{quote_scalar(namespace.uri)}") if namespace.uri
          line("prefix #{quote_scalar(namespace.prefix)}") if namespace.prefix
        end
      end

      def render_package(package)
        render_block("#{declaration_visibility(package.visibility)}package #{package.name}") do
          render_collection(package, :classes) { |item| render_class(item) }
          render_collection(package, :enums) { |item| render_enum(item) }
          render_collection(package, :data_types) { |item| render_data_type(item) }
          render_collection(package, :packages) { |item| render_package(item) }
        end
      end

      def render_class(klass)
        render_block(class_header(klass)) do
          render_comments(klass.comments)
          member { render_definition(klass.definition) } if definition_present?(klass.definition)
          member { render_class_namespace(klass.xml_namespace) } if klass.xml_namespace&.uri
          Array(klass.attributes).each { |attribute| member { render_attribute(attribute) } }
          Array(klass.operations).each { |operation| member { render_operation(operation) } }
          Array(klass.derived_fields).each do |field|
            member { line("derive #{field.name}: #{field.type}") }
          end
          Array(klass.string_formats).each { |format| member { render_string_format(format) } }
          Array(klass.serialization_mappings).each do |mapping|
            member { render_mapping(mapping, with_target: false) }
          end
        end
      end

      def render_class_namespace(namespace)
        text = "namespace #{quote_always(namespace.uri)}"
        text += " prefix #{quote_always(namespace.prefix)}" if namespace.prefix
        line(text)
      end

      def class_header(klass)
        text = "#{declaration_visibility(klass.visibility)}#{class_modifier(klass)}"
        text += "class #{klass.name}"
        parent = klass.parent_class.to_s.empty? ? klass.type : klass.parent_class
        text += " < #{parent}" if parent.to_s != ''
        text + stereotype_suffix(klass.stereotype)
      end

      def class_modifier(klass)
        return "#{klass.modifier} " if klass.modifier.to_s != ''

        klass.is_abstract ? 'abstract ' : ''
      end

      def render_enum(enum)
        render_block("#{declaration_visibility(enum.visibility)}enum #{enum.name}#{stereotype_suffix(enum.stereotype)}") do
          member { render_definition(enum.definition) } if definition_present?(enum.definition)
          member { line('abstract true') } if enum.is_abstract
          member { render_member_fields(enum.member_fields) } if Array(enum.member_fields).any?
          member { render_from_table(enum) } if enum.from_table_name
          Array(enum.attributes).each { |value| member { render_enum_member(value) } }
        end
      end

      def render_member_fields(fields)
        render_block('member_fields') do
          Array(fields).each { |field| line("#{field.name} #{field.type}") }
        end
      end

      def render_from_table(enum)
        header = "from_table #{quote_scalar(enum.from_table_name)}"
        if enum.from_table_artifact.to_s.empty?
          line(header)
        else
          render_block(header) do
            line("artifact #{quote_scalar(enum.from_table_artifact)}")
          end
        end
      end

      def render_enum_member(value)
        return render_attribute(value) if attribute_member?(value)

        description = Array(value.attributes).find { |attribute| attribute.name == 'description' }
        properties = Array(value.properties)
        instances = Array(value.instances)
        payload = description || properties.any? || instances.any?

        unless payload
          line("value #{quote_scalar(value.name)}")
          return
        end

        render_block("value #{quote_scalar(value.name)}") do
          member { render_definition(description.type) } if description
          properties.each do |property|
            member { line("#{property.name} = #{render_data_value(unwrap(property.value))}") }
          end
          instances.each { |instance| member { render_instance(instance) } }
        end
      end

      # A member carrying the attribute shape (type, visibility, direct
      # definition, cardinality, options) came from a bare attribute
      # declaration, not from the `value` construct. Rendering it as a
      # `value` block would move a direct definition into the nested
      # description payload and change the model.
      def attribute_member?(value)
        value.type.to_s != '' ||
          !public_visibility?(value.visibility) ||
          definition_present?(value.definition) ||
          value.cardinality || Array(value.value_set).any? ||
          value.pattern || value.default ||
          Array(value.stereotype).any? || value.literal
      end

      def render_data_type(data_type)
        render_block("#{declaration_visibility(data_type.visibility)}data_type #{data_type.name}#{stereotype_suffix(data_type.stereotype)}") do
          member { render_definition(data_type.definition) } if definition_present?(data_type.definition)
          Array(data_type.attributes).each { |attribute| member { render_attribute(attribute) } }
        end
      end

      def render_primitive(primitive)
        line("#{declaration_visibility(primitive.visibility)}primitive #{primitive.name}")
      end

      def render_mapping(mapping, with_target: true)
        target = with_target && mapping.target.to_s != '' ? " #{mapping.target}" : ''
        render_block("mapping #{mapping.format}#{target}") do
          line("element #{quote_always(mapping.element_name)}") if mapping.element_name
          line("namespace #{mapping.namespace_ref}") if mapping.namespace_ref
          line('mixed_content') if mapping.mixed_content
          Array(mapping.rules).each do |rule|
            text = mapping_rule(rule)
            line(text) if text
          end
        end
      end

      def mapping_rule(rule)
        case rule.kind.to_s
        when 'element' then "map_element #{wire_and_field(rule)}"
        when 'attribute' then "map_attribute #{wire_and_field(rule)}"
        when 'content' then "map_content #{rule.field}"
        when 'namespace' then "namespace #{rule.field || rule.wire}"
        when 'key' then "map_key to_instance #{rule.field}"
        when 'value'
          mode = rule.mode.to_s.empty? ? 'to_instance' : rule.mode
          "map_value #{mode} #{rule.field}"
        else "map #{wire_and_field(rule)}"
        end
      end

      def wire_and_field(rule)
        parts = []
        parts << quote_always(rule.wire) if rule.wire
        parts << rule.field if rule.field
        parts.join(' ')
      end

      def render_association(association)
        name = association.name.to_s.empty? ? '' : " #{association.name}"
        render_block("association#{name}") do
          member { line("owner_type #{association.owner_end_type}") } if association.owner_end_type
          member { line("member_type #{association.member_end_type}") } if association.member_end_type
          member { line(association_end('owner', association.owner_end, association.owner_end_attribute_name, association.owner_end_cardinality)) } if association.owner_end
          member { line(association_end('member', association.member_end, association.member_end_attribute_name, association.member_end_cardinality)) } if association.member_end
        end
      end

      def association_end(keyword, name, attribute_name, cardinality)
        text = "#{keyword} #{quote_scalar(name)}"
        text += "##{attribute_name}" if attribute_name.to_s != ''
        text += " [#{cardinality_token(cardinality)}]" if cardinality
        text
      end

      def render_diagram(diagram)
        return if diagram.name.to_s.empty?

        render_block("diagram #{diagram.name}") do
          member { render_definition(diagram.definition) } if definition_present?(diagram.definition)
        end
      end

      # ---- attributes ----

      def render_attribute(attribute)
        return if attribute.name.to_s.empty?

        return render_attribute_block(attribute) if attribute.xml_role && attribute_block_options?(attribute)

        if terse_attribute?(attribute)
          line("attribute #{attribute.name}, #{attribute.type}")
        elsif naked_attribute?(attribute)
          line("#{visibility_symbol(attribute.visibility)}#{attribute_name_text(attribute.name)}")
        elsif bare_attribute?(attribute)
          render_bare_attribute(attribute)
        else
          render_attribute_block(attribute)
        end
      end

      def attribute_block_options?(attribute)
        Array(attribute.value_set).any? || Array(attribute.properties).any? ||
          !attribute.pattern.nil? || !attribute.default.nil?
      end

      def terse_attribute?(attribute)
        public_visibility?(attribute.visibility) &&
          bare_name?(attribute.name) &&
          attribute.type.to_s != '' &&
          attribute_cardinality(attribute).nil? &&
          Array(attribute.value_set).empty? &&
          Array(attribute.properties).empty? &&
          attribute.pattern.nil? && attribute.default.nil? &&
          Array(attribute.stereotype).empty? && !attribute.literal &&
          attribute.xml_role.nil? && !definition_present?(attribute.definition)
      end

      def naked_attribute?(attribute)
        public_visibility?(attribute.visibility) &&
          attribute.type.to_s.empty? &&
          attribute_cardinality(attribute).nil? &&
          Array(attribute.value_set).empty? &&
          Array(attribute.properties).empty? &&
          attribute.pattern.nil? && attribute.default.nil? &&
          Array(attribute.stereotype).empty? && !attribute.literal &&
          attribute.xml_role.nil? && !definition_present?(attribute.definition)
      end

      def bare_attribute?(attribute)
        !public_visibility?(attribute.visibility) ||
          !bare_name?(attribute.name) ||
          Array(attribute.stereotype).any? || attribute.literal ||
          !attribute.xml_role.nil? || definition_present?(attribute.definition)
      end

      def render_bare_attribute(attribute)
        header = "#{visibility_symbol(attribute.visibility)}#{attribute_name_text(attribute.name)}"
        type = attribute_type_text(attribute)
        header += ": #{type}" if type != ''
        cardinality = attribute_cardinality(attribute)
        header += " [#{cardinality}]" if cardinality
        header += " as :#{attribute.xml_role}" if attribute.xml_role

        if definition_present?(attribute.definition)
          render_block(header) { render_definition(attribute.definition) }
        else
          line(header)
        end
      end

      def bare_name?(name)
        name.to_s.match?(%r{\A[A-Za-z0-9_/+]+\z})
      end

      def attribute_name_text(name)
        bare_name?(name) ? name.to_s : quote_always(name)
      end

      def attribute_type_text(attribute)
        return '' if attribute.type.to_s.empty?

        stereotypes = Array(attribute.stereotype)
        type = attribute.literal ? quote_always(attribute.type) : attribute.type.to_s
        stereotypes.any? ? "<<#{stereotypes.first}>> #{type}" : type
      end

      def render_attribute_block(attribute)
        header = "attribute #{attribute_name_text(attribute.name)}"
        header += " as :#{attribute.xml_role}" if attribute.xml_role
        render_block(header) do
          line("type #{attribute.type}") if attribute.type.to_s != ''
          cardinality = attribute_cardinality(attribute)
          line("cardinality #{cardinality}") if cardinality
          if Array(attribute.value_set).any?
            values = attribute.value_set.map { |value| quote_scalar(value) }.join(', ')
            line("values { #{values} }")
          end
          line("default #{render_data_value(attribute.default)}") if attribute.default

          properties = Array(attribute.properties)
          defaults, others = properties.partition { |property| property.name == 'default' }
          defaults.each { |property| line(property_line(property)) }
          line("pattern /#{attribute.pattern}/") if attribute.pattern
          others.sort_by { |property| property.name.to_s }
                .each { |property| line(property_line(property)) }
        end
      end

      def property_line(property)
        "#{property.name} = #{render_data_value(unwrap(property.value))}"
      end

      def render_operation(operation)
        parameters = Array(operation.owned_parameter).map do |parameter|
          operation_parameter(parameter)
        end.join(', ')
        text = "#{visibility_symbol(operation.visibility)}#{operation.name}(#{parameters})"
        text += ": #{operation.return_type}" if operation.return_type.to_s != ''
        stereotypes = Array(operation.stereotype)
        text += " { #{stereotypes.join(', ')} }" if stereotypes.any?
        line(text)
      end

      def operation_parameter(parameter)
        parts = []
        direction = parameter.direction.to_s
        parts << direction if !direction.empty? && direction != 'in'
        parts << parameter.name
        parts << ": #{parameter.type}" if parameter.type.to_s != ''
        parts << "= #{render_data_value(parameter.default)}" unless parameter.default.nil?
        parts.join(' ')
      end

      def render_string_format(format)
        render_block("string_format #{quote_scalar(format.format)}") do
          line("artifact #{quote_scalar(format.artifact)}") if format.artifact
          line("root #{quote_scalar(format.root)}") if format.root
        end
      end

      # ---- instances ----

      def render_instance_collection(collection)
        name = collection.name.to_s.empty? ? '' : " #{quote_scalar(collection.name)}"
        render_block("instances#{name}") do
          Array(collection.imports).each { |entry| member { render_import(entry) } }
          Array(collection.collections).each { |entry| member { render_collection_decl(entry) } }
          Array(collection.exports).each { |entry| member { render_export(entry) } }
          Array(collection.instances).each { |entry| member { render_instance(entry) } }
        end
      end

      def render_import(entry)
        render_block('import') do
          member do
            render_block("#{entry.format_type} #{quote_always(entry.file)}") do
              Array(entry.attributes).each do |attribute|
                member { render_instance_attribute(attribute) }
              end
            end
          end
        end
      end

      def render_export(entry)
        render_block('export') do
          member do
            render_block("format #{entry.format_type}") do
              Array(entry.attributes).each do |attribute|
                member { render_instance_attribute(attribute) }
              end
            end
          end
        end
      end

      def render_collection_decl(collection)
        render_block("collection #{quote_always(collection.name)}") do
          if Array(collection.includes).any?
            values = collection.includes.map { |value| quote_always(value) }.join(', ')
            member { line("includes [#{values}]") }
          end
          next if Array(collection.validations).empty?

          member do
            render_block('validation') do
              Array(collection.validations).each do |condition|
                line("condition #{quote_always(condition)}")
              end
            end
          end
        end
      end

      def render_instance(instance, prefix = '')
        render_block("#{prefix}#{instance_header(instance)}") do
          member { line("isa #{quote_scalar(instance.isa)}") } if instance.isa.to_s != ''
          if Array(instance.template).any?
            member { render_template(instance.template) }
          else
            Array(instance.attributes).each do |attribute|
              member { render_instance_attribute(attribute) }
            end
          end
          member { render_instance(instance.instance) } if instance.instance
        end
      end

      def instance_header(instance)
        label =
          if instance.name.to_s.empty?
            instance.type.to_s.empty? ? 'instance' : "instance #{instance.type}"
          elsif instance.type.to_s.empty?
            "instance #{quote_always(instance.name)}"
          else
            "#{instance.type} #{quote_always(instance.name)}"
          end
        label += " extends #{quote_always(instance.parent)}" if instance.parent.to_s != ''
        label
      end

      def render_instance_attribute(attribute)
        if attribute.name.to_s.empty?
          render_definition(attribute.definition, force_block: true) if definition_present?(attribute.definition)
          return
        end

        # `# text` inside an instance body parses as an attribute named
        # Comment with no type. Emitting it as a normal assignment would
        # reintroduce a String type on the next parse.
        if attribute.name == 'Comment' && attribute.type.to_s.empty?
          line("# #{unwrap(attribute.value)}")
          return
        end

        if Array(attribute.instances).any?
          render_instance_values(attribute)
        else
          line("#{assignment_prefix(attribute)}#{render_data_value(unwrap(attribute.value))}")
        end
      end

      # `name += value` extends an inherited value; the grammar stores
      # that as the `extended` flag.
      def assignment_prefix(attribute)
        marker = attribute.extended ? '+' : ''
        "#{quote_scalar(attribute.name)} #{marker}= "
      end

      def render_instance_values(attribute)
        values = Array(attribute.instances)
        if values.one?
          render_instance(values.first, assignment_prefix(attribute))
          return
        end

        line("#{assignment_prefix(attribute)}[")
        @level += 1
        values.each { |instance| render_instance(instance) }
        @level -= 1
        line(']')
      end

      def render_template(entries)
        render_block('template') do
          Array(entries).each do |entry|
            member { render_instance_attribute(entry) }
          end
        end
      end

      # ---- values ----

      def render_data_value(value)
        value = unwrap(value)
        case value
        when nil then 'null'
        when Float then number_scalar(value)
        when true, false, Integer then value.to_s
        when String then quote_always(value)
        when Array
          "[#{value.map { |item| render_data_value(item) }.join(', ')}]"
        when Hash
          reference = value[:reference] || value['reference']
          return "ref:(#{reference})" if reference

          pairs = value.map do |key, item|
            "#{quote_scalar(key)} = #{render_data_value(item)}"
          end
          "{ #{pairs.join(' ')} }"
        else
          quote_always(value.to_s)
        end
      end

      def unwrap(value)
        value = value.value while value.is_a?(Lutaml::Lml::LiteralValue)
        value
      end

      def cardinality_token(cardinality)
        min = cardinality.min.to_s
        max = cardinality.max.to_s
        max = 'n' if max == '*'
        max.empty? ? min : "#{min}..#{max}"
      end

      def attribute_cardinality(attribute)
        cardinality = attribute.cardinality
        return nil if cardinality.nil?

        token = cardinality_token(cardinality)
        token == '0..1' ? nil : token
      end

      # ---- definitions and comments ----

      def definition_present?(definition)
        text = definition_text(definition)
        !(text.nil? || text.empty?)
      end

      def definition_text(definition)
        definition&.to_s
      end

      def render_definition(definition, force_block: false)
        text = definition_text(definition)
        return if text.nil? || text.empty?

        if force_block || text.include?("\n")
          render_definition_block(text)
        else
          line("definition #{quote_always(text)}")
        end
      end

      def render_definition_block(text)
        line('definition {')
        @level += 1
        text.split("\n", -1).each do |part|
          part.empty? ? (@lines << '') : line(escape_braces(part))
        end
        @level -= 1
        trim_trailing_blanks
        line('}')
      end

      def escape_braces(text)
        text.gsub(/[{}]/) { |brace| "\\#{brace}" }
      end

      def render_comments(comments)
        Array(comments).each { |comment| member { render_comment(comment) } }
      end

      def render_comment(comment)
        text = comment.to_s
        if text.include?("\n")
          line("*|#{text}|*")
        elsif text.empty?
          line('**')
        else
          line("** #{text}")
        end
      end

      # ---- headers ----

      def declaration_visibility(visibility)
        word = visibility.to_s
        VISIBILITY_WORDS.include?(word) ? "#{word} " : ''
      end

      def visibility_symbol(visibility)
        VISIBILITY_SYMBOLS.fetch(visibility.to_s, '')
      end

      def public_visibility?(visibility)
        visibility.nil? || visibility.to_s.empty? || visibility.to_s == 'public'
      end

      def stereotype_suffix(stereotypes)
        values = Array(stereotypes)
        values.empty? ? '' : " <<#{values.first}>>"
      end

      # ---- layout ----

      def render_collection(owner, collection)
        Array(owner.public_send(collection)).each do |item|
          member { yield item }
        end
      end

      def render_block(header)
        line("#{header} {")
        @level += 1
        @bodies.push(@lines.length)
        yield
        @bodies.pop
        @level -= 1
        trim_trailing_blanks
        line('}')
      end

      def member
        blank_line if @bodies.any? && @lines.length > @bodies.last
        yield
      end

      def top
        blank_line if @bodies.empty? || @lines.length > @bodies.last
        yield
      end

      def line(text)
        @lines << "#{'  ' * @level}#{text}"
      end

      def blank_line
        @lines << '' unless @lines.empty? || @lines.last == ''
      end

      def trim_trailing_blanks
        @lines.pop while @lines.last == ''
      end
    end
  end
end
