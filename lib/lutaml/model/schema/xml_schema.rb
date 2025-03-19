# frozen_string_literal: true

require "erb"
require "tmpdir"
require "lutaml/xsd"
require_relative "xml_schema/utility_helper"
require_relative "xml_schema/simple_type"
require_relative "xml_schema/groups"

module Lutaml
  module Model
    module Schema
      module XmlSchema
        extend self

        attr_reader :simple_types,
                    :group_types,
                    :complex_types,
                    :elements,
                    :attributes,
                    :attribute_groups

        DEFAULT_CLASSES = %w[string integer int boolean date].freeze
        ELEMENT_ORDER_IGNORABLE = %w[import include].freeze

        MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true

          require "lutaml/model"
          <%=
            requiring_files = UtilityHelper.resolve_required_files(content)
            requiring_files.join("\n") + "\n" if requiring_files&.any?
          -%>

          class <%= Utils.camel_case(name) %> < <%= resolve_parent_class(content) %>
          <%= UtilityHelper.render_definition_content(content, options) %>
          <%=
            #UtilityHelper::NOT_IMPLEMENTED
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
                render_default = ", render_default: true" if attribute.key_exist?(:default)
                "    map_attribute :\#{attribute.name}, to: :\#{Utils.snake_case(attribute.name)}\#{render_default}"
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          -%>
          <%=
            if content.keys.any? { |key| %i[sequence choice].include?(key) }
              output = resolve_content(content).map do |element_name, element|
                next if element_name == :arguments

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
                  element.map do |attribute|
                    render_default = ", render_default: true" if attribute.key_exist?(:default)
                    "    map_attribute :\#{attribute.name}, to: :\#{Utils.snake_case(attribute.name)}\#{render_default}"
                  end.join("\n")
                else
                  element = @elements[element.ref_class.split(":")&.last] if element&.key_exist?(:ref_class)
                  next if element_name == :arguments

                  "    map_element :\#{element_name}, to: :\#{Utils.snake_case(element_name)}"
                end
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          -%>
            end
          end

          Lutaml::Model::Register.register_model(:<%= Utils.snake_case(name)&.to_sym %>, <%= Utils.camel_case(name) %>)
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
          options[:indent] = options[:indent] ? options[:indent].to_i : 2
          options[:current_indent] = " " * options[:indent]
          setup_dependencies(options: options)
          if options[:create_files]
            dir = options.fetch(:output_dir, "lutaml_models_#{Time.now.to_i}")
            FileUtils.mkdir_p(dir)
            @data_types_classes.merge(@importable_classes).each do |name, content|
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
            group_types = @importable_classes.each do |name, content|
              create_file(name, content, dir)
            end
            complex_types = @complex_types.to_h do |name, content|
              [Utils.camel_case(name), MODEL_TEMPLATE.result(binding)]
            end
            classes_hash = simple_types.merge(group_types).merge(complex_types)
            require_classes(classes_hash) if options[:load_classes]
            classes_hash
          end
        end

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

        def setup_dependencies(options: {})
          @data_types_classes = XmlSchema::SimpleType.create_simple_types(@simple_types)
          @importable_classes = XmlSchema::Groups.create_groups(
            @group_types,
            options: options,
          )
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
            schema_to_models(schema.include) if schema.include&.any?
            schema_to_models(schema.import) if schema.import&.any?

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
          hash[:length] = restriction_length(restriction.length) if restriction.length&.any?
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
            hash[:attributes] = [] if complex_type&.attribute&.any?
            hash[:attribute_groups] = [] if complex_type&.attribute_group&.any?
            hash[:mixed] = complex_type.mixed
            resolved_element_order(complex_type).each do |element|
              case element
              when Xsd::Attribute
                hash[:attributes] << setup_attribute(element)
              when Xsd::Sequence
                hash[:sequence] = setup_sequence(element)[:sequence]
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
            setup_min_max_arguments(sequence, hash)
            hash[:sequence] = resolved_element_order(sequence).map do |instance|
              case instance
              when Xsd::Sequence
                setup_sequence(instance)
              when Xsd::Element
                setup_element(instance)
              when Xsd::Choice
                { choice: setup_choice(instance) }
              when Xsd::Group
                { groups: setup_group_type(instance) }
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
            setup_min_max_arguments(choice, hash)
            resolved_element_order(choice).each do |element|
              case element
              when Xsd::Element
                hash.assign_or_append_value(:elements, setup_element(element))
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
            if ref = attribute.ref
              attr_hash[:ref_class] = ref
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
              hash[:attributes] = [] if attribute_group.attribute&.any?
              hash[:attribute_groups] = [] if attribute_group.attribute_group&.any?
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
            if ref = element.ref
              hash[:element_ref] = ref.split(":").last
            else
              setup_min_max_arguments(element, hash)
              hash[:element_name] = element.name
              hash[:type_name] = if element.complex_type || element.simple_type
                                   setup_element_type(element)
                                 else
                                   element.type
                                 end
            end
          end
        end

        def setup_element_type(element)
          type = element.simple_type ? "simple" : "complex"
          type_object = element.public_send(:"#{type}_type")
          prefix = type == "simple" ? "ST_" : "CT_"
          type_object_name = "#{prefix}#{element.name}"
          object_value = public_send(:"setup_#{type}_type", type_object)
          instance_variable_get(:"@#{type}_types")[type_object_name] = object_value
          type_object_name
        end

        def setup_restriction(restriction, hash)
          hash[:base_class] = restriction.base
          restriction_patterns(restriction.pattern, hash) if restriction.respond_to?(:pattern)
          restriction_content(hash, restriction)
          return hash unless restriction.respond_to?(:enumeration) && restriction.enumeration&.any?

          hash[:values] = restriction.enumeration.map(&:value)
          hash
        end

        def restriction_patterns(patterns, hash)
          return if Utils.blank?(patterns)

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
            resolved_element_order(extension).each do |element|
              case element
              when Xsd::Attribute
                hash.assign_or_append_value(:attributes, [setup_attribute(element)])
              when Xsd::Sequence
                hash.assign_or_append_value(:sequence, setup_sequence(element))
              when Xsd::Choice
                hash.assign_or_append_value(:choice, setup_choice(element))
              end
            end
          end
        end

        def setup_min_max_arguments(object, object_hash)
          MappingHash.new.tap do |hash|
            hash[:min_occurs] = object.min_occurs if object.min_occurs
            hash[:max_occurs] = object.max_occurs if object.max_occurs
            object_hash[:arguments] = hash if hash.any?
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

        def resolve_mapping_content(content, hash = MappingHash.new)
          content.each do |key, value|
            case key
            when :sequence
              hash[:sequence] = resolve_sequence(value, hash)
            end
          end
        end

        def resolve_content(content, hash = MappingHash.new)
          content.each do |key, value|
            case key
            when :sequence
              resolve_sequence(value, hash)
            when :choice
              resolve_choice(value, hash)
            when :attributes, :mixed
              # NOTE: these are not to be processed
            else
              raise "#{caller}: #{key} is not supported"
            end
          end
          hash
        end

        def resolve_sequence(sequence, hash = MappingHash.new)
          sequence.each do |content|
            if content.key?(:element_ref)
              element = @elements[content.element_ref]
              hash[element.element_name] = element
            elsif content.key?(:sequence)
              resolve_sequence(content, hash)
            elsif content.key?(:choice)
              resolve_choice(content[:choice], hash)
            elsif content.key?(:groups)
              # NO ACTION REQUIRED: Groups are imported at the definition.
            end
          end
          hash
        end

        def resolve_choice(choice, hash = MappingHash.new)
          choice.each do |key, value|
            case key
            when :elements
              element = @elements[content.element_ref]
              hash[element.element_name] = element
            when :sequence
              resolve_sequence(value, hash)
            when :arguments
              hash[:arguments] = value
            when :group
              # NO ACTION REQUIRED: Groups are imported at the definition.
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
          ", default: -> { #{resolve_attribute_default_value(klass, default)} }"
        end

        def resolve_attribute_default_value(klass, default)
          case klass
          when "int", "integer", "date", "boolean"
            cast_default(klass, default)
          else
            default.inspect
          end
        end

        def cast_default(klass, value)
          klass = "integer" if klass == "int"

          Lutaml::Model::Type.const_get(klass.capitalize).cast(value)
        end

        def resolve_namespace(options)
          namespace_str = "namespace \"#{options[:namespace]}\"" if options.key?(:namespace)
          namespace_str += ", \"#{options[:prefix]}\"" if options.key?(:prefix) && options.key?(:namespace)
          namespace_str += "\n" if namespace_str
          namespace_str
        end

        # END: TEMPLATE RESOLVER METHODS

        def attributes_presentation(current_indent, attribute)
          output = "#{current_indent}attribute :#{Utils.snake_case(attribute.name)}, #{resolve_attribute_class(attribute)}"
          output += resolve_attribute_default(attribute) if attribute.key_exist?(:default)
          output += "\n"
          output
        end
      end
    end
  end
end
