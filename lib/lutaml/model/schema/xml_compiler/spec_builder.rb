# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # Walks parsed XSD AST objects and emits Definitions::* specs.
        # Holds the in-progress class hashes that ref resolution looks
        # up by name. Stateful by design (refs and forward references
        # demand it); kept out of XmlCompiler.rb so the orchestrator
        # stays focused on parse/dispatch.
        class SpecBuilder
          # XSD built-in type table. Keys are the XSD type names; values
          # describe how to render the generated subclass.
          # `skippable: true` means the XSD type maps directly to a
          # Lutaml primitive symbol and needs no generated class.
          TC = Lutaml::Model::Type::TYPE_CODES

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { skippable: false, class_name: TC[:string],
                                  validations: { pattern: /\+?[0-9]+/ } },
            normalizedString: { skippable: false, class_name: TC[:string],
                                validations: { transform: "value.gsub(/[\\r\\n\\t]/, ' ')" } },
            positiveInteger: { skippable: false, class_name: TC[:integer],
                               validations: { min_inclusive: 0 } },
            unsignedShort: { skippable: false, class_name: TC[:integer],
                             validations: { min_inclusive: 0, max_inclusive: 65535 } },
            base64Binary: { skippable: false, class_name: TC[:string],
                            validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedLong: { skippable: false, class_name: TC[:integer],
                            validations: { min_inclusive: 0, max_inclusive: 18446744073709551615 } },
            unsignedByte: { skippable: false, class_name: TC[:integer],
                            validations: { min_inclusive: 0, max_inclusive: 255 } },
            unsignedInt: { skippable: false, class_name: TC[:integer],
                           validations: { min_inclusive: 0, max_inclusive: 4294967295 } },
            hexBinary: { skippable: false, class_name: TC[:string],
                         validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            language: { skippable: false, class_name: TC[:string],
                        validations: { pattern: /\A[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*\z/ } },
            dateTime: { skippable: true, class_name: TC[:date_time] },
            boolean: { skippable: true, class_name: TC[:boolean] },
            integer: { skippable: true, class_name: TC[:integer] },
            decimal: { skippable: true, class_name: TC[:decimal] },
            string: { skippable: true, class_name: TC[:string] },
            double: { skippable: true, class_name: TC[:float] },
            NCName: { skippable: false, class_name: TC[:string],
                      validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
            anyURI: { skippable: false, class_name: TC[:string],
                      validations: { pattern: "\\A\#{URI::DEFAULT_PARSER.make_regexp(%w[http https ftp])}\\z" } },
            token: { skippable: false, class_name: TC[:string],
                     validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            byte: { skippable: false, class_name: TC[:integer],
                    validations: { min_inclusive: -128, max_inclusive: 127 } },
            long: { skippable: false, class_name: TC[:decimal] },
            int: { skippable: true, class_name: TC[:integer] },
            id: { skippable: false, class_name: TC[:string],
                  validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
          }.freeze

          attr_reader :simple_types, :complex_types, :group_types,
                      :elements, :attributes, :attribute_groups,
                      :namespace_classes

          def initialize
            @simple_types = MappingHash.new
            @complex_types = MappingHash.new
            @group_types = MappingHash.new
            @elements = MappingHash.new
            @attributes = MappingHash.new
            @attribute_groups = MappingHash.new
            @namespace_classes = MappingHash.new
          end

          def populate_default_attributes
            XmlCompiler::XML_DEFINED_ATTRIBUTES.each do |name, w3c_class|
              @attributes[name] = Definitions::Attribute.new(
                name: Utils.snake_case(name),
                type: Definitions::TypeRef.new(kind: :w3c, value: w3c_class),
                xml_name: name,
                kind: :attribute,
              )
            end
          end

          def collect_namespaces(schemas, options)
            @user_requested_namespace_uri = options[:namespace]
            uris = Set.new
            uris.add(@user_requested_namespace_uri) if @user_requested_namespace_uri
            schemas.each do |schema|
              uris.add(schema.target_namespace) if schema.target_namespace
            end
            uris.each do |uri|
              next if uri.nil? || uri.empty?

              prefix = options[:prefix] if @user_requested_namespace_uri == uri
              ns = Definitions::Namespace.new(
                class_name: NamespaceNaming.class_name_for(uri),
                uri: uri,
                prefix_default: prefix || NamespaceNaming.prefix_for(uri),
              )
              @namespace_classes[ns.class_name] = ns
            end
          end

          def walk_schemas(schemas)
            return if schemas.empty?

            # Two-pass walk: register top-level Elements / Attributes /
            # AttributeGroups / SimpleTypes first so forward references
            # from ComplexTypes / Groups resolve in pass 2.
            collect_lookups(schemas)
            build_complex_types(schemas)
          end

          def collect_lookups(schemas)
            schemas.each do |schema|
              collect_lookups(schema.include) if schema.include&.any?
              collect_lookups(schema.import)  if schema.import&.any?
              schema.resolved_element_order.each do |item|
                dispatch_lookup(item, schema)
              end
            end
          end

          def build_complex_types(schemas)
            schemas.each do |schema|
              build_complex_types(schema.include) if schema.include&.any?
              build_complex_types(schema.import)  if schema.import&.any?
              within_namespace(schema.target_namespace) do
                schema.resolved_element_order.each do |item|
                  dispatch_complex(item, schema)
                end
              end
            end
          end

          # Sets @current_namespace_class_name for the duration of the
          # block so build_complex_type / build_group_model can attach
          # the right namespace to each generated Definitions::Model.
          # Only attaches when the schema's target namespace matches the
          # one the caller explicitly asked for via `options[:namespace]`.
          def within_namespace(uri)
            previous = @current_namespace_class_name
            @current_namespace_class_name = namespace_class_name_for(uri)
            yield
          ensure
            @current_namespace_class_name = previous
          end

          def namespace_class_name_for(uri)
            return nil if uri.nil? || uri.empty?
            return nil unless uri == @user_requested_namespace_uri

            ns = @namespace_classes.values.find { |n| n.uri == uri }
            ns&.class_name
          end

          def dispatch_lookup(item, schema)
            case item
            when Lutaml::Xml::Schema::Xsd::SimpleType
              @simple_types[item.name] = build_simple_type(item)
            when Lutaml::Xml::Schema::Xsd::Element
              @elements[item.name] = build_top_level_attribute(item, kind: :element)
            when Lutaml::Xml::Schema::Xsd::Attribute
              return if xml_defined_attribute?(schema, item.name)

              @attributes[item.name] = build_top_level_attribute(item, kind: :attribute)
            when Lutaml::Xml::Schema::Xsd::AttributeGroup
              @attribute_groups[item.name] = build_attribute_group_members(item)
            end
          end

          def dispatch_complex(item, _schema)
            case item
            when Lutaml::Xml::Schema::Xsd::ComplexType
              @complex_types[item.name] = build_complex_type(item)
            when Lutaml::Xml::Schema::Xsd::Group
              @group_types[item.name] = build_group_model(item)
            end
          end

          # Add the built-in XSD types (NonNegativeInteger, NormalizedString,
          # etc.) as Definitions::RestrictedType entries.
          def add_supported_types
            SUPPORTED_DATA_TYPES.each do |name, info|
              next if info[:skippable]

              str_name = name.to_s
              @simple_types[str_name] = build_supported_type(str_name, info)
            end
          end

          private

          def dispatch_top_level(item, schema)
            case item
            when Lutaml::Xml::Schema::Xsd::SimpleType
              @simple_types[item.name] = build_simple_type(item)
            when Lutaml::Xml::Schema::Xsd::ComplexType
              @complex_types[item.name] = build_complex_type(item)
            when Lutaml::Xml::Schema::Xsd::Group
              @group_types[item.name] = build_group_model(item)
            when Lutaml::Xml::Schema::Xsd::Element
              @elements[item.name] = build_top_level_attribute(item, kind: :element)
            when Lutaml::Xml::Schema::Xsd::Attribute
              return if xml_defined_attribute?(schema, item.name)

              @attributes[item.name] = build_top_level_attribute(item, kind: :attribute)
            when Lutaml::Xml::Schema::Xsd::AttributeGroup
              @attribute_groups[item.name] = build_attribute_group_members(item)
            end
          end

          def xml_defined_attribute?(schema, name)
            schema.target_namespace == XmlCompiler::XML_NAMESPACE_URI &&
              XmlCompiler::XML_DEFINED_ATTRIBUTES.key?(name)
          end

          # ----------------------------------------------------------------
          # Simple types
          # ----------------------------------------------------------------

          def build_simple_type(simple_type)
            if (union = simple_type.union)
              build_union_type(simple_type.name, union.member_types.split)
            else
              build_restricted_type(simple_type.name, simple_type.restriction)
            end
          end

          def build_union_type(name, member_type_names)
            type_refs = member_type_names.map do |raw|
              snake = Utils.snake_case(Utils.last_of_split(raw))
              Definitions::TypeRef.new(kind: :symbol, value: snake)
            end
            Definitions::UnionType.new(
              class_name: Utils.camel_case(name),
              members: type_refs,
              cast_strategy: :resolve_type,
              required_files: union_required_files(member_type_names),
              lazy_register: true,
              keep_register_when_namespaced: true,
            )
          end

          def union_required_files(member_type_names)
            member_type_names.filter_map do |raw|
              local = Utils.last_of_split(raw)
              next if SUPPORTED_DATA_TYPES.dig(local.to_sym, :skippable)

              %(require_relative "#{Utils.snake_case(local)}")
            end
          end

          def build_restricted_type(name, restriction)
            base_class = restriction&.base&.split(":")&.last
            facet = build_facet(restriction) if restriction
            transform = nil
            parent = restricted_parent_class(base_class)

            Definitions::RestrictedType.new(
              class_name: Utils.camel_case(name),
              parent_class: parent,
              facets: facet || Definitions::Facet.new,
              transform_facet: transform,
              required_files: restricted_required_files(base_class),
              keep_register_when_namespaced: true,
            )
          end

          # Mirror RestrictedSimpleType#parent_class behavior.
          def restricted_parent_class(base_class)
            type_info = SUPPORTED_DATA_TYPES[base_class&.to_sym]
            return type_info[:class_name] if type_info&.dig(:skippable)
            return Utils.camel_case(base_class.to_s) if !type_info&.dig(:skippable) && Utils.present?(base_class)

            "Lutaml::Model::Type::Value"
          end

          def restricted_required_files(base_class)
            return [] if Utils.blank?(base_class)

            sym = base_class.to_sym
            return [%(require "bigdecimal")] if sym == :decimal
            return [] if SUPPORTED_DATA_TYPES.dig(sym, :skippable)

            [%(require_relative "#{Utils.snake_case(base_class)}")]
          end

          def build_supported_type(name, info)
            base = Utils.base_class_snake_case(info[:class_name])
            validations = info[:validations] || {}
            facet = Definitions::Facet.new(
              min_inclusive: validations[:min_inclusive],
              max_inclusive: validations[:max_inclusive],
              pattern: validations[:pattern],
            )
            transform = validations[:transform] && Definitions::TransformFacet.new(expression: validations[:transform])

            Definitions::RestrictedType.new(
              class_name: Utils.camel_case(name),
              parent_class: restricted_parent_class(base),
              facets: facet,
              transform_facet: transform,
              required_files: supported_type_required_files(base),
              keep_register_when_namespaced: true,
            )
          end

          def supported_type_required_files(base_class)
            return [] if Utils.blank?(base_class)
            return [] if SUPPORTED_DATA_TYPES.dig(base_class.to_sym, :skippable)

            [%(require_relative "#{Utils.snake_case(base_class)}")]
          end

          # ----------------------------------------------------------------
          # Facets
          # ----------------------------------------------------------------

          def build_facet(restriction)
            facet = Definitions::Facet.new(
              max_length: pick_minmax(restriction.max_length, :min),
              min_length: pick_minmax(restriction.min_length, :max),
              min_inclusive: pick_minmax(restriction.min_inclusive, :max),
              max_inclusive: pick_minmax(restriction.max_inclusive, :min),
              max_exclusive: pick_minmax(restriction.max_exclusive, :max),
              min_exclusive: pick_minmax(restriction.min_exclusive, :min),
              length: restriction.length&.any? ? restriction_length(restriction.length) : nil,
              pattern: build_pattern(restriction.pattern),
              enumerations: restriction.enumeration&.any? ? restriction.enumeration.map(&:value) : nil,
            )
            facet
          end

          def pick_minmax(field_value, method)
            return nil unless field_value&.any?

            field_value.map(&:value).public_send(method).to_s
          end

          def restriction_length(lengths)
            lengths.map { |l| { value: l.value, fixed: l.fixed } }
          end

          def build_pattern(patterns)
            return nil if Utils.blank?(patterns)

            patterns.map { |p| "(#{p.value})" }.join("|")
          end

          # ----------------------------------------------------------------
          # Complex types
          # ----------------------------------------------------------------

          def build_complex_type(complex_type)
            model = Definitions::Model.new(
              class_name: Utils.camel_case(complex_type.name),
              xml_root: Definitions::XmlRoot.new(kind: :element, name: complex_type.name),
              mixed: !!complex_type.mixed,
              namespace_class_name: @current_namespace_class_name,
            )

            resolved_element_order(complex_type).each do |element|
              add_complex_child(model, element)
            end
            model
          end

          def add_complex_child(model, element)
            case element
            when Lutaml::Xml::Schema::Xsd::Attribute
              attr = build_attribute_def(element)
              model.members << attr if attr
            when Lutaml::Xml::Schema::Xsd::Sequence
              model.members << build_sequence(element, model)
            when Lutaml::Xml::Schema::Xsd::Choice
              model.members << build_choice(element, model)
            when Lutaml::Xml::Schema::Xsd::ComplexContent
              apply_complex_content(element, model)
            when Lutaml::Xml::Schema::Xsd::AttributeGroup
              model.members.concat(build_attribute_group_members(element))
            when Lutaml::Xml::Schema::Xsd::Group
              add_group_to_model(element, model)
            when Lutaml::Xml::Schema::Xsd::SimpleContent
              model.simple_content = build_simple_content(element)
            end
          end

          def apply_complex_content(content, model)
            model.mixed = true if content.mixed

            if (ext = content.extension)
              model.parent_class = qualified_class(ext.base)
              resolved_element_order(ext).each { |c| add_complex_child(model, c) }
            elsif (res = content.restriction)
              model.parent_class = qualified_class(res.base)
              resolved_element_order(res).each do |c|
                # XSD: restrictions on complex content inherit sequence/choice/group from base.
                next if c.is_a?(Lutaml::Xml::Schema::Xsd::Sequence) ||
                  c.is_a?(Lutaml::Xml::Schema::Xsd::Choice) ||
                  c.is_a?(Lutaml::Xml::Schema::Xsd::Group)

                add_complex_child(model, c)
              end
            end
          end

          def qualified_class(raw)
            return "Lutaml::Model::Serializable" if raw.nil?

            Utils.camel_case(Utils.last_of_split(raw))
          end

          def add_group_to_model(group, model)
            # Anonymous group OR named-but-not-referenced group: unwrap
            # the inner sequence/choice inline into the model. (Matches
            # the old XmlCompiler::Group rendering, which only emitted
            # import_model_attributes/mappings when `ref` was set.)
            if group.ref.nil?
              add_anonymous_group_contents(group, model)
              @group_types[group.name] = build_group_model(group) if group.name && !@group_types.key?(group.name)
              return
            end

            base = Utils.snake_case(Utils.last_of_split(group.ref)).to_sym
            model.attribute_directives << "import_model_attributes :#{base}"
            model.mapping_directives << "import_model_mappings :#{base}"
          end

          def add_anonymous_group_contents(group, model)
            inner = group.sequence || group.choice
            return unless inner

            built = case inner
                    when Lutaml::Xml::Schema::Xsd::Sequence then build_sequence(inner)
                    when Lutaml::Xml::Schema::Xsd::Choice   then build_choice(inner)
                    end
            model.members << built if built
          end

          # ----------------------------------------------------------------
          # Attributes / elements
          # ----------------------------------------------------------------

          def build_attribute_def(attr)
            return resolve_attribute_ref(attr) if attr.ref && !attr.name

            type_str = resolve_attribute_type(attr)
            Definitions::Attribute.new(
              name: Utils.snake_case(attr.name),
              type: build_type_ref(type_str),
              xml_name: attr.name,
              kind: :attribute,
              default: attr.default,
            )
          end

          def resolve_attribute_ref(attr)
            base_name = Utils.last_of_split(attr.ref)
            target = @attributes[base_name]
            return nil unless target

            Definitions::Attribute.new(
              name: target.name,
              type: target.type,
              xml_name: target.xml_name,
              kind: :attribute,
              default: target.default,
            )
          end

          def resolve_attribute_type(attr)
            return attr.type if attr.type

            anon = attr.simple_type
            anon_name = "ST_#{attr.name}"
            anon.name = anon_name
            @simple_types[anon_name] = build_simple_type(anon)
            anon_name
          end

          def build_top_level_attribute(item, kind:)
            return item unless item.respond_to?(:name) # passthrough for now

            type_str = if item.respond_to?(:type) && item.type
                        item.type
                      elsif item.respond_to?(:simple_type) && item.simple_type
                        resolve_top_level_simple(item)
                      elsif item.respond_to?(:complex_type) && item.complex_type
                        resolve_top_level_complex(item)
                      end
            Definitions::Attribute.new(
              name: Utils.snake_case(item.name.to_s),
              type: build_type_ref(type_str || "string"),
              xml_name: item.name.to_s,
              kind: kind,
            )
          end

          def resolve_top_level_simple(item)
            anon = item.simple_type
            anon_name = "ST_#{item.name}"
            anon.name = anon_name
            @simple_types[anon_name] = build_simple_type(anon)
            anon_name
          end

          def resolve_top_level_complex(item)
            anon = item.complex_type
            anon_name = "CT_#{item.name}"
            anon.name = anon_name
            @complex_types[anon_name] = build_complex_type(anon)
            anon_name
          end

          def build_element_def(element)
            return resolve_element_ref(element) if element.ref && !element.name

            type_str = resolve_element_type(element)
            min_occ, max_occ = element.min_occurs, element.max_occurs
            Definitions::Attribute.new(
              name: Utils.snake_case(element.name),
              type: build_type_ref(type_str),
              xml_name: element.name,
              kind: :element,
              collection: collection_from_occurs(min_occ, max_occ),
              default: element.default,
              render_default: !element.default.nil?,
              render_empty: element_required?(min_occ),
            )
          end

          def resolve_element_ref(element)
            base_name = Utils.last_of_split(element.ref)
            target = @elements[base_name]
            return nil unless target

            Definitions::Attribute.new(
              name: target.name,
              type: target.type,
              xml_name: target.xml_name,
              kind: :element,
              collection: collection_from_occurs(element.min_occurs, element.max_occurs),
              default: target.default,
              render_default: !target.default.nil?,
              render_empty: element_required?(element.min_occurs),
            )
          end

          def resolve_element_type(element)
            return element.type if element.type

            if element.simple_type
              anon = element.simple_type
              anon_name = "ST_#{element.name}"
              anon.name = anon_name
              @simple_types[anon_name] = build_simple_type(anon)
              return anon_name
            end

            if element.complex_type
              anon = element.complex_type
              anon_name = "CT_#{element.name}"
              anon.name = anon_name
              @complex_types[anon_name] = build_complex_type(anon)
              return anon_name
            end

            "string"
          end

          def collection_from_occurs(min_occurs, max_occurs)
            return false if min_occurs.nil? && max_occurs.nil?

            min = min_occurs.nil? ? 1 : min_occurs.to_i
            max = case max_occurs
                  when "unbounded" then Float::INFINITY
                  when NilClass    then 1
                  else max_occurs.to_i
                  end
            return false if min == 1 && max == 1

            (min..max)
          end

          def element_required?(min_occurs)
            min_occurs.nil? || min_occurs.to_i >= 1
          end

          def build_type_ref(raw_type)
            return Definitions::TypeRef.new(kind: :symbol, value: "string") if raw_type.nil?
            return Definitions::TypeRef.new(kind: :w3c, value: raw_type) if w3c_type?(raw_type)

            local = Utils.last_of_split(raw_type)
            Definitions::TypeRef.new(kind: :symbol, value: Utils.snake_case(local))
          end

          def w3c_type?(raw_type)
            raw_type.to_s.start_with?("Lutaml::Xml::W3c::")
          end

          # ----------------------------------------------------------------
          # Sequence / Choice
          # ----------------------------------------------------------------

          def build_sequence(sequence, model = nil)
            members = []
            resolved_element_order(sequence).each do |item|
              next if item.is_a?(Lutaml::Xml::Schema::Xsd::Any)

              member = build_sequence_member(item, model)
              members << member if member
            end
            Definitions::Sequence.new(members: members)
          end

          def build_sequence_member(item, model)
            case item
            when Lutaml::Xml::Schema::Xsd::Sequence then build_sequence(item, model)
            when Lutaml::Xml::Schema::Xsd::Element  then build_element_def(item)
            when Lutaml::Xml::Schema::Xsd::Choice   then build_choice(item, model)
            when Lutaml::Xml::Schema::Xsd::Group
              add_group_to_model(item, model) if model
              nil
            end
          end

          def build_choice(choice, model = nil)
            alternatives = []
            resolved_element_order(choice).each do |item|
              member = case item
                       when Lutaml::Xml::Schema::Xsd::Element  then build_element_def(item)
                       when Lutaml::Xml::Schema::Xsd::Sequence then build_sequence(item, model)
                       when Lutaml::Xml::Schema::Xsd::Choice   then build_choice(item, model)
                       when Lutaml::Xml::Schema::Xsd::Group
                         add_group_to_model(item, model) if model
                         nil
                       end
              alternatives << member if member
            end
            Definitions::Choice.new(
              alternatives: alternatives,
              header: choice_header(choice),
            )
          end

          def choice_header(choice)
            min = choice.min_occurs.nil? ? 1 : choice.min_occurs.to_i
            max = case choice.max_occurs
                  when "unbounded" then "Float::INFINITY"
                  when NilClass    then 1
                  else choice.max_occurs.to_i
                  end
            "choice(min: #{min}, max: #{max})"
          end

          # ----------------------------------------------------------------
          # Groups (importable type-only models)
          # ----------------------------------------------------------------

          def build_group_model(group)
            inner_members = []
            inner = group.sequence || group.choice
            if inner
              built = case inner
                      when Lutaml::Xml::Schema::Xsd::Sequence then build_sequence(inner)
                      when Lutaml::Xml::Schema::Xsd::Choice   then build_choice(inner)
                      end
              inner_members << built if built
            end

            base_name = group.name || Utils.last_of_split(group.ref)
            # Groups render unwrapped (module_wrappable: false) so they
            # cannot reference the namespace constant by bare name.
            # Importers inherit the namespace from the wrapping class.
            Definitions::Model.new(
              class_name: Utils.camel_case(base_name),
              xml_root: Definitions::XmlRoot.new(kind: :type_name, name: base_name),
              members: inner_members,
              module_wrappable: false,
              lazy_register: true,
            )
          end

          # ----------------------------------------------------------------
          # Attribute groups (flattened into model.members)
          # ----------------------------------------------------------------

          def build_attribute_group_members(attribute_group)
            ref = attribute_group.ref
            if ref && !attribute_group.name
              target = @attribute_groups[Utils.last_of_split(ref)]
              return Array(target)
            end

            members = []
            resolved_element_order(attribute_group).each do |item|
              case item
              when Lutaml::Xml::Schema::Xsd::Attribute
                attr_spec = build_attribute_def(item)
                members << attr_spec if attr_spec
              when Lutaml::Xml::Schema::Xsd::AttributeGroup
                members.concat(build_attribute_group_members(item))
              end
            end
            members
          end

          # ----------------------------------------------------------------
          # Simple content (XSD-only)
          # ----------------------------------------------------------------

          def build_simple_content(simple_content)
            additional = []
            base_class = nil
            required_files = []
            if simple_content.extension
              ext = simple_content.extension
              base_class = ext.base
              resolved_element_order(ext).each do |item|
                next unless item.is_a?(Lutaml::Xml::Schema::Xsd::Attribute)

                attr = build_attribute_def(item)
                additional << attr if attr
              end
            elsif simple_content.restriction
              base_class = simple_content.restriction.base
            end
            required_files << simple_content_required_file(base_class) if base_class

            Definitions::SimpleContent.new(
              base_class: base_class,
              additional_attributes: additional,
              required_files: required_files.compact,
            )
          end

          def simple_content_required_file(base_class)
            local = Utils.last_of_split(base_class)
            return nil if SUPPORTED_DATA_TYPES.dig(local.to_sym, :skippable)

            %(require_relative "#{Utils.snake_case(local)}")
          end

          # ----------------------------------------------------------------
          # Element ordering helper (mirrors original behavior).
          # ----------------------------------------------------------------

          def resolved_element_order(object)
            return [] if object.element_order.nil?

            if object.is_a?(Lutaml::Xml::Schema::Xsd::Base)
              return object.resolved_element_order
            end

            object.element_order.each_with_object(object.element_order.dup) do |builder, array|
              next array.delete(builder) if builder.text? || XmlCompiler::ELEMENT_ORDER_IGNORABLE.include?(builder.name)

              index = 0
              array.each_with_index do |element, i|
                next unless element == builder

                array[i] = Array(object.public_send(Utils.snake_case(builder.name)))[index]
                index += 1
              end
            end
            object.element_order
          end
        end
      end
    end
  end
end
