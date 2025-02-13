# frozen_string_literal: true

require "erb"
require "tmpdir"
require "lutaml/xsd"
require_relative "templates/simple_type"

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        extend self

        DEFAULT_CLASSES = %w[string integer int boolean].freeze
        ELEMENT_ORDER_IGNORABLE = %w[import include].freeze

        MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true
          require "lutaml/model"
          <%=
            requiring_files = resolve_required_files(content)
            if requiring_files.any?
              requiring_files.map { |file| "require_relative \\\"\#{file}\\\"" }.join("\n") + "\n"
            end
          -%>

          class <%= Utils.camel_case(name) %> < <%= resolve_parent_class(content) %>
          <%=
            if content&.key_exist?(:attributes)
              output = content.attributes.map do |attribute|
                attribute = @attributes[attribute.ref_class.split(":").last] if attribute.key?(:ref_class)
                "  attribute :\#{Utils.snake_case(attribute.name)}, \#{resolve_attribute_class(attribute)}\#{resolve_attribute_default(attribute) if attribute.key_exist?(:default)}"
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          -%>
          <%=
            if content&.key_exist?(:sequence) || content&.key_exist?(:choice) || content&.key_exist?(:group)
              output = resolve_content(content).map do |element_name, element|
                element = @elements[element.ref_class.split(":")&.last] if element&.key_exist?(:ref_class)
                "  attribute :\#{Utils.snake_case(element_name)}, \#{resolve_element_class(element)}\#{resolve_occurs(element.arguments) if element.key_exist?(:arguments)}"
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          -%>
          <%=
            if content&.key_exist?(:complex_content)
              resolve_complex_content(content.complex_content).map do |element_name, element|
                if element_name == :attributes
                  element.map { |attribute| "  attribute :\#{Utils.snake_case(attribute.name)}, \#{resolve_attribute_class(attribute)}\#{resolve_attribute_default(attribute.default) if attribute.key_exist?(:default)}" }.join("\n")
                else
                  element = @elements[element.ref_class.split(":")&.last] if element&.key_exist?(:ref_class)
                  "  attribute :\#{Utils.snake_case(element_name)}, \#{resolve_element_class(element)}\#{resolve_occurs(element.arguments) if element.key_exist?(:arguments)}"
                end
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          -%>
          <%= "  attribute :content, \#{content[:mixed] ? ':string' : content.simple_content.extension_base}" if content_exist = (content.key_exist?(:simple_content) && content.simple_content.key_exist?(:extension_base)) || content[:mixed] -%>

            xml do
              root "<%= name %>", mixed: true
          <%= resolve_namespace(options) %>
          <%= "    map_content to: :content\n" if content_exist -%>
          <%=
            if content&.key_exist?(:attributes)
              output = content.attributes.map do |attribute|
                attribute = @attributes[attribute.ref_class.split(":").last] if attribute.key?(:ref_class)
                "    map_attribute :\#{Utils.snake_case(attribute.name)}, to: :\#{Utils.snake_case(attribute.name)}"
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          -%>
          <%=
            if content&.key_exist?(:sequence) || content&.key_exist?(:choice) || content&.key_exist?(:group)
              output = resolve_content(content).map do |element_name, element|
                element = @elements[element.ref_class.split(":")&.last] if element&.key_exist?(:ref_class)
                "    map_element :\#{element_name}, to: :\#{Utils.snake_case(element_name)}"
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          -%>
          <%=
            if content&.key_exist?(:complex_content)
              output = resolve_complex_content(content.complex_content).map do |element_name, element|
                if element_name == :attributes
                  element.map { |attribute| "    map_attribute :\#{Utils.snake_case(attribute.name)}, to: :\#{Utils.snake_case(attribute.name)}" }.join("\n")
                else
                  element = @elements[element.ref_class.split(":")&.last] if element&.key_exist?(:ref_class)
                  "    map_element :\#{element_name}, to: :\#{Utils.snake_case(element_name)}"
                end
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          -%>
            end
          end

        TEMPLATE

        XML_ADAPTER_NOT_SET_MESSAGE = <<~MSG
          Nokogiri is not set as XML Adapter.
          Make sure Nokogiri is installed and set as XML Adapter eg.
          execute: gem install nokogiri
          require 'lutaml/model/adapter/nokogiri'
          Lutaml::Model.xml_adapter = Lutaml::Model::Adapter::Nokogiri
        MSG

        def to_models(schema, options = {})
          as_models(schema, options: options)
          @data_types_classes = Templates::SimpleType.create_simple_types(@simple_types)
          if options[:create_files]
            dir = options.fetch(:output_dir, "lutaml_models_#{Time.now.to_i}")
            FileUtils.mkdir_p(dir)
            @data_types_classes.each do |name, content|
              create_file(name, content, dir)
            end
            @complex_types.each do |name, content|
              create_file(name, MODEL_TEMPLATE.result(binding), dir)
            end
            nil
          else
            simple_types = @data_types_classes.transform_keys do |key|
              Utils.camel_case(key.to_s)
            end
            complex_types = @complex_types.to_h do |name, content|
              [Utils.camel_case(name), MODEL_TEMPLATE.result(binding)]
            end
            classes_hash = simple_types.merge(complex_types)
            require_classes(classes_hash) if options[:load_classes]
            classes_hash
          end
        end

        private

        def create_file(name, content, dir)
          File.write("#{dir}/#{Utils.snake_case(name)}.rb", content)
        end

        def require_classes(classes_hash)
          Dir.mktmpdir do |dir|
            classes_hash.each do |name, klass|
              create_file(name, klass, dir)
              require "#{dir}/#{Utils.snake_case(name)}"
            end
          end
        end

        # START: STRUCTURE SETUP METHODS

        def as_models(schema, options: {})
          raise Error, XML_ADAPTER_NOT_SET_MESSAGE unless Config.xml_adapter.name.end_with?("NokogiriAdapter")

          parsed_schema = Xsd.parse(schema, location: options[:location])

          @elements = MappingHash.new
          @attributes = MappingHash.new
          @group_types = MappingHash.new
          @simple_types = MappingHash.new
          @complex_types = MappingHash.new
          @attribute_groups = MappingHash.new

          schema_to_models(Array(parsed_schema))
        end

        def schema_to_models(schemas)
          return if schemas.empty?

          schemas.each do |schema|
            schema_to_models(schema.include) if schema.include.any?
            schema_to_models(schema.import) if schema.import.any?
            resolved_element_order(schema).each do |order_item|
              item_name = order_item&.name
              case order_item
              when Xsd::SimpleType
                @simple_types[item_name] = setup_simple_type(order_item)
              when Xsd::Group
                @group_types[item_name] = setup_group_type(order_item)
              when Xsd::ComplexType
                @complex_types[item_name] = setup_complex_type(order_item)
              when Xsd::Element
                @elements[item_name] = setup_element(order_item)
              when Xsd::Attribute
                @attributes[item_name] = setup_attribute(order_item)
              when Xsd::AttributeGroup
                @attribute_groups[item_name] = setup_attribute_groups(order_item)
              end
            end
          end
          nil
        end

        def setup_simple_type(simple_type)
          MappingHash.new.tap do |hash|
            setup_restriction(simple_type.restriction, hash) if simple_type&.restriction
            hash[:union] = setup_union(simple_type.union) if simple_type.union
          end
        end

        def restriction_content(hash, restriction)
          return hash unless restriction.respond_to?(:max_length)

          hash[:max_length] = restriction.max_length.map(&:value).min if restriction.max_length&.any?
          hash[:min_length] = restriction.min_length.map(&:value).max if restriction.min_length&.any?
          hash[:min_inclusive] = restriction.min_inclusive.map(&:value).max if restriction.min_inclusive&.any?
          hash[:max_inclusive] = restriction.max_inclusive.map(&:value).min if restriction.max_inclusive&.any?
          hash[:length] = restriction_length(restriction.length) if restriction.length.any?
        end

        def restriction_length(lengths)
          lengths.map do |length|
            MappingHash.new.tap do |hash|
              hash[:value] = length.value
              hash[:fixed] = length.fixed if length.fixed
            end
          end
        end

        def setup_complex_type(complex_type)
          MappingHash.new.tap do |hash|
            hash[:attributes] = [] if complex_type.attribute.any?
            hash[:attribute_groups] = [] if complex_type.attribute_group.any?
            hash[:mixed] = complex_type.mixed
            resolved_element_order(complex_type).each do |element|
              case element
              when Xsd::Attribute
                hash[:attributes] << setup_attribute(element)
              when Xsd::Sequence
                hash[:sequence] = setup_sequence(element)
              when Xsd::Choice
                hash[:choice] = setup_choice(element)
              when Xsd::ComplexContent
                hash[:complex_content] = setup_complex_content(element)
              when Xsd::AttributeGroup
                hash[:attribute_groups] << setup_attribute_groups(element)
              when Xsd::Group
                hash[:group] = setup_group_type(element)
              when Xsd::SimpleContent
                hash[:simple_content] = setup_simple_content(element)
              end
            end
          end
        end

        def setup_simple_content(simple_content)
          if simple_content.extension
            setup_extension(simple_content.extension)
          elsif simple_content.restriction
            setup_restriction(simple_content.restriction, {})
          end
        end

        def setup_sequence(sequence)
          MappingHash.new.tap do |hash|
            hash[:sequences] = [] if sequence.sequence.any?
            hash[:elements] = [] if sequence.element.any?
            hash[:choice] = [] if sequence.choice.any?
            hash[:groups] = [] if sequence.group.any?
            resolved_element_order(sequence).each do |instance|
              case instance
              when Xsd::Sequence
                hash[:sequences] << setup_sequence(instance)
              when Xsd::Element
                hash[:elements] << if instance.name
                  setup_element(instance)
                else
                  create_mapping_hash(instance.ref, hash_key: :ref_class)
                end
              when Xsd::Choice
                hash[:choice] << setup_choice(instance)
              when Xsd::Group
                hash[:groups] << if instance.name
                  setup_group_type(instance)
                else
                  create_mapping_hash(instance.ref, hash_key: :ref_class)
                end
              when Xsd::Any
                # No implementation yet!
              end
            end
          end
        end

        def setup_group_type(group)
          MappingHash.new.tap do |hash|
            if group.ref
              hash[:ref_class] = group.ref
            else
              resolved_element_order(group).map do |instance|
                case instance
                when Xsd::Sequence
                  hash[:sequence] = setup_sequence(instance)
                when Xsd::Choice
                  hash[:choice] = setup_choice(instance)
                end
              end
            end
          end
        end

        def setup_choice(choice)
          MappingHash.new.tap do |hash|
            resolved_element_order(choice).each do |element|
              case element
              when Xsd::Element
                element_name = element.name || @elements[element.ref.split(":").last]&.element_name
                hash[element_name] = setup_element(element)
              when Xsd::Sequence
                hash[:sequence] = setup_sequence(element)
              when Xsd::Group
                hash[:group] = setup_group_type(element)
              when Xsd::Choice
                hash[:choice] = setup_choice(element)
              end
            end
          end
        end

        def setup_union(union)
          union.member_types.split.map do |member_type|
            @simple_types[member_type]
          end.flatten
        end

        def setup_attribute(attribute)
          MappingHash.new.tap do |attr_hash|
            if attribute.ref
              attr_hash[:ref_class] = attribute.ref
            else
              attr_hash[:name] = attribute.name
              attr_hash[:base_class] = attribute.type
              attr_hash[:default] = attribute.default if attribute.default
            end
          end
        end

        def setup_attribute_groups(attribute_group)
          MappingHash.new.tap do |hash|
            if attribute_group.ref
              hash[:ref_class] = attribute_group.ref
            else
              hash[:attributes] = [] if attribute_group.attribute.any?
              hash[:attribute_groups] = [] if attribute_group.attribute_group.any?
              resolved_element_order(attribute_group).each do |instance|
                case instance
                when Xsd::Attribute
                  hash[:attributes] << setup_attribute(instance)
                when Xsd::AttributeGroup
                  hash[:attribute_groups] << setup_attribute_groups(instance)
                end
              end
            end
          end
        end

        def create_mapping_hash(value, hash_key: :class_name)
          MappingHash.new.tap do |hash|
            hash[hash_key] = value
          end
        end

        def setup_element(element)
          MappingHash.new.tap do |hash|
            if element.ref
              hash[:ref_class] = element.ref
            else
              hash[:type_name] = element.type
              hash[:element_name] = element.name
              element_arguments(element, hash)
              return hash unless complex_type = element.complex_type

              hash[:complex_type] = setup_complex_type(complex_type)
              @complex_types[complex_type.name] = hash[:complex_type]
            end
          end
        end

        def setup_restriction(restriction, hash)
          hash[:base_class] = restriction.base
          restriction_patterns(restriction.pattern, hash) if restriction.respond_to?(:pattern)
          restriction_content(hash, restriction)
          return hash unless restriction.respond_to?(:enumeration) && restriction.enumeration.any?

          hash[:values] = restriction.enumeration.map(&:value)
          hash
        end

        def restriction_patterns(patterns, hash)
          return if patterns.empty?

          hash[:pattern] = patterns.map { |p| "(#{p.value})" }.join("|")
          hash
        end

        def setup_complex_content(complex_content)
          MappingHash.new.tap do |hash|
            hash[:mixed] = true if complex_content.mixed
            if complex_content.extension
              hash[:extension] = setup_extension(complex_content.extension)
            elsif restriction = complex_content.restriction
              setup_restriction(restriction, hash)
            end
          end
        end

        def setup_extension(extension)
          MappingHash.new.tap do |hash|
            hash[:extension_base] = extension.base
            hash[:attribute_groups] = [] if extension&.attribute_group&.any?
            hash[:attributes] = [] if extension&.attribute&.any?
            resolved_element_order(extension).each do |element|
              case element
              when Xsd::Attribute
                hash[:attributes] << setup_attribute(element)
              when Xsd::Sequence
                hash[:sequence] = setup_sequence(element)
              when Xsd::Choice
                hash[:choice] = setup_choice(element)
              end
            end
          end
        end

        def element_arguments(element, element_hash)
          MappingHash.new.tap do |hash|
            hash[:min_occurs] = element.min_occurs if element.min_occurs
            hash[:max_occurs] = element.max_occurs if element.max_occurs
            element_hash[:arguments] = hash if hash.any?
          end
        end

        def resolved_element_order(object)
          return [] if object.element_order.nil?

          object.element_order.each_with_object(object.element_order.dup) do |builder_instance, array|
            next array.delete(builder_instance) if builder_instance.text?
            next array.delete(builder_instance) if ELEMENT_ORDER_IGNORABLE.include?(builder_instance.name)

            index = 0
            array.each_with_index do |element, i|
              next unless element == builder_instance

              array[i] = Array(object.send(Utils.snake_case(builder_instance.name)))[index]
              index += 1
            end
          end
        end

        # END: STRUCTURE SETUP METHODS

        # START: TEMPLATE RESOLVER METHODS
        def resolve_parent_class(content)
          return "Lutaml::Model::Serializable" unless content.dig(:complex_content, :extension)

          Utils.camel_case(content.dig(:complex_content, :extension, :extension_base))
        end

        def resolve_attribute_class(attribute)
          attr_class = attribute.base_class.split(":")&.last
          case attr_class
          when *DEFAULT_CLASSES
            ":#{attr_class}"
          else
            Utils.camel_case(attr_class)
          end
        end

        def resolve_element_class(element)
          element_class = element.type_name.split(":").last
          case element_class
          when *DEFAULT_CLASSES
            ":#{element_class}"
          else
            Utils.camel_case(element_class)
          end
        end

        def resolve_occurs(arguments)
          min_occurs = arguments[:min_occurs]
          max_occurs = arguments[:max_occurs]
          max_occurs = max_occurs.to_s&.match?(/[A-Za-z]+/) ? nil : max_occurs.to_i if max_occurs
          ", collection: #{max_occurs ? min_occurs.to_i..max_occurs : true}"
        end

        def resolve_content(content, hash = MappingHash.new)
          content.each do |key, value|
            case key
            when :sequence
              resolve_sequence(value, hash)
            when :choice
              resolve_choice(value, hash)
            when :group
              resolve_group(value, hash)
            end
          end
          hash
        end

        def resolve_elements(elements, hash = MappingHash.new)
          elements.each do |element|
            if element.key?(:ref_class)
              new_element = @elements[element.ref_class.split(":").last]
              hash[new_element.element_name] = new_element
            else
              hash[element.element_name] = element
            end
          end
          hash
        end

        def resolve_sequence(sequence, hash = MappingHash.new)
          sequence.each do |key, value|
            case key
            when :sequence
              resolve_sequence(value, hash)
            when :elements
              resolve_elements(value, hash)
            when :groups
              value.each { |group| resolve_group(group, hash) }
            when :choice
              value.each { |choice| resolve_choice(choice, hash) }
            end
          end
          hash
        end

        def resolve_choice(choice, hash = MappingHash.new)
          choice.each do |key, value|
            case key
            when :element
              [resolve_elements(value, hash)]
            when :group
              resolve_group(value, hash)
            when String
              hash[key] = value
            when :sequence
              resolve_sequence(value, hash)
            end
          end
          hash
        end

        def resolve_group(group, hash = MappingHash.new)
          group.each do |key, value|
            case key
            when :ref_class
              resolve_group(@group_types[value.split(":").last], hash)
            when :choice
              resolve_choice(value, hash)
            when :group
              resolve_group(value, hash)
            when :sequence
              resolve_sequence(value, hash)
            end
          end
          hash
        end

        def resolve_complex_content(complex_content, hash = MappingHash.new)
          complex_content.each do |key, value|
            case key
            when :extension
              resolve_extension(value, hash)
            when :restriction
              # TODO: No implementation yet!
              hash
            end
          end
          hash
        end

        def resolve_extension(extension, hash = MappingHash.new)
          hash[:attributes] = extension.attributes if extension.key?(:attributes)
          resolve_sequence(extension.sequence, hash) if extension.key?(:sequence)
          resolve_choice(extension.choice, hash) if extension.key?(:choice)
          hash
        end

        def resolve_attribute_default(attribute)
          klass = attribute.base_class.split(":").last
          default = attribute[:default]
          ", default: #{resolve_attribute_default_value(klass, default)}"
        end

        def resolve_attribute_default_value(klass, default)
          return default.inspect unless DEFAULT_CLASSES.include?(klass)

          klass = "integer" if klass == "int"
          type_klass = Lutaml::Model::Type.const_get(klass.capitalize)
          type_klass.cast(default)
        end

        def resolve_namespace(options)
          namespace_str = "namespace \"#{options[:namespace]}\"" if options.key?(:namespace)
          namespace_str += ", \"#{options[:prefix]}\"" if options.key?(:prefix) && options.key?(:namespace)
          namespace_str += "\n" if namespace_str
          namespace_str
        end

        def resolve_required_files(content)
          @required_files = []
          content.each do |key, value|
            case key
            when :sequence
              required_files_sequence(value)
            when :choice
              required_files_choice(value)
            when :group
              required_files_group(value)
            when :attributes
              required_files_attribute(value)
            when :attribute_groups
              value.each do |attribute_group|
                required_files_attribute_groups(attribute_group)
              end
            when :complex_content
              required_files_complex_content(value)
            when :simple_content
              required_files_simple_content(value)
            end
          end
          @required_files.uniq.sort_by(&:length)
        end

        # END: TEMPLATE RESOLVER METHODS

        # START: REQUIRED FILES LIST COMPILER METHODS
        def required_files_simple_content(simple_content)
          simple_content.each do |key, value|
            case key
            when :extension_base
              # Do nothing.
            when :attributes
              required_files_attribute(value)
            when :extension
              required_files_extension(value)
            when :restriction
              required_files_restriction(value)
            end
          end
        end

        def required_files_complex_content(complex_content)
          complex_content.each do |key, value|
            case key
            when :extension
              required_files_extension(value)
            when :restriction
              required_files_restriction(value)
            end
          end
        end

        def required_files_extension(extension)
          extension.each do |key, value|
            case key
            when :attribute_group
              required_files_attribute_groups(value)
            when :attribute, :attributes
              required_files_attribute(value)
            when :extension_base
              # Do nothing.
            when :sequence
              required_files_sequence(value)
            when :choice
              required_files_choice(value)
            end
          end
        end

        def required_files_restriction(restriction)
          restriction.each do |key, value|
            case key
            when :base
              @required_files << Utils.snake_case(value.split(":").last)
            end
          end
        end

        def required_files_attribute_groups(attr_groups)
          attr_groups.each do |key, value|
            case key
            when :ref_class
              required_files_attribute_groups(@attribute_groups[value.split(":").last])
            when :attribute, :attributes
              required_files_attribute(value)
            end
          end
        end

        def required_files_attribute(attributes)
          attributes.each do |attribute|
            next if attribute[:ref_class]&.start_with?("xml") || attribute[:base_class]&.start_with?("xml")

            attribute = @attributes[attribute.ref_class.split(":").last] if attribute.key_exist?(:ref_class)
            attr_class = attribute.base_class.split(":")&.last
            next if DEFAULT_CLASSES.include?(attr_class)

            @required_files << Utils.snake_case(attr_class)
          end
        end

        def required_files_choice(choice)
          choice.each do |key, value|
            case key
            when String
              value = @elements[value.ref_class.split(":").last] if value.key?(:ref_class)
              @required_files << Utils.snake_case(value.type_name.split(":").last)
            when :element
              required_files_elements(value)
            when :group
              required_files_group(value)
            when :choice
              required_files_choice(value)
            when :sequence
              required_files_sequence(value)
            end
          end
        end

        def required_files_group(group)
          group.each do |key, value|
            case key
            when :ref_class
              required_files_group(@group_types[value.split(":").last])
            when :choice
              required_files_choice(value)
            when :sequence
              required_files_sequence(value)
            end
          end
        end

        def required_files_sequence(sequence)
          sequence.each do |key, value|
            case key
            when :elements
              required_files_elements(value)
            when :sequence
              required_files_sequence(value)
            when :groups
              value.each { |group| required_files_group(group) }
            when :choice
              value.each { |choice| required_files_choice(choice) }
            end
          end
        end

        def required_files_elements(elements)
          elements.each do |element|
            element = @elements[element.ref_class.split(":").last] if element.key_exist?(:ref_class)
            element_class = element.type_name.split(":").last
            next if DEFAULT_CLASSES.include?(element_class)

            @required_files << Utils.snake_case(element_class)
          end
        end

        # END: REQUIRED FILES LIST COMPILER METHODS
      end
    end
  end
end
