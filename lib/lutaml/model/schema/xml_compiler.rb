# frozen_string_literal: true

require 'erb'
require 'lutaml/xsd'
require_relative 'templates/simple_type'

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        extend self

        DEFAULT_CLASSES = %w[string integer int boolean].freeze

        MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: '-')
          # frozen_string_literal: true

          <%= resolve_required_files(content).map { |file| "require_relative \\\"\#{file}\\\"" }.join("\n") -%>

          class <%= Utils.camel_case(name) %> < <%= resolve_parent_class(content) %>
          <% content&.key_exist?(:attributes) && content.attributes.each do |attribute| -%><% attribute = @attributes[attribute.ref_class.split(":").last] if attribute.key?(:ref_class) %>
            attribute :<%= Utils.snake_case(attribute.name) %>, <%= resolve_attribute_class(attribute) %>
          <%- end -%><% content&.key_exist?(:sequence) && resolve_sequence(content.sequence).each do |element_name, element| %><% element = @elements[element.ref_class.split(':')&.last] if element&.key_exist?(:ref_class) %>
            attribute :<%= Utils.snake_case(element_name) %>, <%= Utils.camel_case(element.type_name.split(':').last) %><% if element.key_exist?(:arguments) %>, <%= resolve_occurs(element.arguments) %>
          <% end %><% end %><% content&.key_exist?(:complex_content) && resolve_complex_content(content.complex_content).each do |element_name, element| %><% if element_name == :attributes %><% element.each do |attribute| %>
            attribute :<%= Utils.snake_case(attribute.name) %>, <%= resolve_attribute_class(attribute) %><% end %><% else %><% element = @elements[element.ref_class.split(':')&.last] if element&.key_exist?(:ref_class) %>
            attribute :<%= Utils.snake_case(element_name) %>, <%= Utils.camel_case(element.type_name.split(':').last) %><% if element.key_exist?(:arguments) %>, <%= resolve_occurs(element.arguments) %><% end %><% end %><% end %>
            <%= "attribute :content, \#{content.simple_content.extension_base}" if content_exist = content.key_exist?(:simple_content) && content.simple_content.key_exist?(:extension_base) %>

            xml do
              root "<%= name %>", mixed: true
              <%= resolve_namespace(options) %>

              <%= "map_content to: :content" if content_exist %>
          <% content&.key_exist?(:attributes) && content.attributes.each do |attribute| -%><% attribute = @attributes[attribute.ref_class.split(":").last] if attribute.key?(:ref_class) %>
              map_attribute :<%= Utils.snake_case(attribute.name) %>, to: :<%= Utils.snake_case(attribute.name) %>
          <% end -%><% content&.key_exist?(:sequence) && resolve_sequence(content.sequence).each do |element_name, element| %><% element = @elements[element.ref_class.split(':')&.last] if element&.key_exist?(:ref_class) %>
              map_element :<%= Utils.snake_case(element_name) %>, to: :<%= Utils.snake_case(element_name) %>
          <% end %><% content&.key_exist?(:complex_content) && resolve_complex_content(content.complex_content).each do |element_name, element| %><% if element_name == :attributes %><% element.each do |attribute| %>
              map_attribute :<%= Utils.snake_case(attribute.name) %>, to: :<%= Utils.snake_case(attribute.name) %><% end %><% else %><% element = @elements[element.ref_class.split(':')&.last] if element&.key_exist?(:ref_class) %>
              map_element :<%= Utils.snake_case(element_name) %>, to: :<%= Utils.snake_case(element_name) %><% end %><% end %>
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

        def as_models(schema, options: {})
          unless Config.xml_adapter ||
                 Config.xml_adapter.name.end_with?('NokogiriAdapter')

            raise Error, XML_ADAPTER_NOT_SET_MESSAGE
          end

          parsed_schema = Xsd.parse(schema, location: options[:location])

          @elements = MappingHash.new
          @attributes = MappingHash.new
          @group_types = MappingHash.new
          @simple_types = MappingHash.new
          @complex_types = MappingHash.new
          @attribute_groups = MappingHash.new

          schema_to_models([parsed_schema])
        end

        def to_models(schema, options: {})
          as_models(schema, options: options)

          @data_types_classes = Templates::SimpleType.create_simple_types(@simple_types)
          @complex_types.to_h do |name, content|
            [name, MODEL_TEMPLATE.result(binding)]
          end
        end

        private

        def schema_to_models(schemas)
          return if schemas.empty?

          schemas.each do |schema|
            schema_to_models(schema.include) if schema.include.any?
            schema_to_models(schema.import) if schema.import.any?
            resolved_element_order(schema).each do |order_item|
              item_name = order_item&.name
              @order_item = order_item&.name == "CT_Settings" ? order_item : nil
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
        end

        def setup_simple_type(simple_type)
          MappingHash.new.tap do |hash|
            setup_restriction(simple_type.restriction, hash) if simple_type&.restriction
            hash[:union] = setup_union(simple_type.union) if simple_type.union
          end
        end

        def restriction_content(hash, restriction)
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
            setup_restriction(simple_content.restriction)
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
              when Xsd::Group
                hash[:groups] << if instance.name
                  setup_group_type(instance)
                else
                  create_mapping_hash(instance.ref, hash_key: :ref_class)
                end
              when Xsd::Choice
                hash[:choice] << setup_choice(instance)
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
              resolved_element_order(group).map do |element|
                case element
                when Xsd::Element
                  hash[element.name] = setup_element(element)
                when Xsd::Sequence
                  hash[:sequence] = setup_sequence(element)
                when Xsd::Choice
                  hash[:choice] = setup_choice(element)
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
                next unless element.name && element.type

                hash[element.name] = setup_element(element)
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
            hash[:element_name] = element.name if element.name
            if element.type
              hash[:type_name] = element.type
            elsif element.ref
              hash[:ref_class] = element.ref
            end
            element_attrs = element_attributes(element)
            hash[:arguments] = element_attrs if element_attrs.any?
            if complex_type = element.complex_type
              hash[:complex_type] = setup_complex_type(element.complex_type)
              @complex_types[element.complex_type.name] = hash[:complex_type]
            end
          end
        end

        def setup_restriction(restriction, hash)
          hash[:base_class] = restriction.base
          hash[:values] = restriction.enumeration.map(&:value) if restriction.enumeration.any?
          hash[:pattern] = restriction_patterns(restriction.pattern) if restriction&.pattern&.any?
          restriction_content(hash, restriction)
        end

        def restriction_patterns(patterns)
          patterns.map { |pattern| "(#{pattern.value})" }.join('|')
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

        def element_attributes(element)
          MappingHash.new.tap do |hash|
            hash[:min_occurs] = element.min_occurs if element.min_occurs
            hash[:max_occurs] = element.max_occurs if element.max_occurs
          end
        end

        def resolved_element_order(object, ignore_text: true)
          object.element_order.each_with_object(object.element_order.dup) do |name, array|
            next array.delete(name) if name == "text" && (ignore_text || !object.respond_to?(:text))
            next array.delete(name) if %w[import include].include?(name)

            index = 0
            array.each_with_index do |element, i|
              next unless element == name

              array[i] = Array(object.send(Utils.snake_case(name)))[index]
              index += 1
            end
          end
        end

        def resolve_parent_class(content)
          return "Lutaml::Model::Serialize" unless content.dig(:complex_content, :extension)

          Utils.camel_case(content.complex_content.extension.extension_base)
        end

        def resolve_type(type)
          @simple_types[type] ||
            @complex_types[type] ||
            type.to_sym
        end

        def resolve_attribute_class(attribute)
          attr_class = attribute.base_class.split(':')&.last
          case attr_class
          when *DEFAULT_CLASSES
            ":#{attr_class}"
          else
            Utils.camel_case(attr_class)
          end
        end

        def resolve_occurs(arguments)
          min_occurs = arguments[:min_occurs]
          max_occurs = arguments[:max_occurs]
          max_occurs = max_occurs&.match?(/[A-Za-z]+/) ? nil : max_occurs.to_i if max_occurs
          "collection: #{max_occurs ? min_occurs.to_i..max_occurs : true}"
        end

        def resolve_elements(elements, hash = MappingHash.new)
          elements.map do |element|
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
          sequence.map do |key, value|
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
          choice.map do |key, value|
            case key
            when :element
              resolve_element(value, hash)
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
          group.map do |key, value|
            case key
            when :ref_class
              resolve_group(@group_types[value.split(":").last])
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
          complex_content.map do |key, value|
            case key
            when :extension
              resolve_extension(value, hash)
            when :restriction
              resolve_restriction(value, hash)
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

        def resolve_restriction(restriction, hash = MappingHash.new)
          restriction.map do |key, value|
            case key
            when :base
              resolve_name(value, hash)
            end
          end
          hash
        end

        def resolve_namespace(options)
          namespace_str = "namespace \"#{options[:namespace]}\"" if options.key?(:namespace)
          namespace_str += ", \"#{options[:prefix]}\"" if options.key?(:prefix) && options.key?(:namespace)
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
              value.each { |attribute_group| required_files_attribute_groups(attribute_group) }
            when :complex_content
              required_files_complex_content(value)
            when :simple_content
              required_files_simple_content(value)
            end
          end
          @required_files.uniq
        end

        def required_files_simple_content(simple_content)
          simple_content.map do |key, value|
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
          complex_content.map do |key, value|
            case key
            when :extension
              required_files_extension(value)
            when :restriction
              required_files_restriction(value)
            end
          end
        end

        def required_files_extension(extension)
          extension.map do |key, value|
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
          restriction.map do |key, value|
            case key
            when :base
              required_files_name(value)
            end
          end
        end

        def required_files_attribute_groups(attribute_groups)
          attribute_groups.map do |key, value|
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
            attr_class = attribute.base_class.split(':')&.last
            next if DEFAULT_CLASSES.include?(attr_class)

            @required_files << Utils.snake_case(attr_class)
          end
        end

        def required_files_choice(choice)
          choice.map do |key, value|
            case key
            when String
              @required_files << Utils.snake_case(value.type_name.split(':').last)
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
          group.map do |key, value|
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
          sequence.map do |key, value|
            case key
            when :elements
              required_files_elements(value)
            when :groups
              value.each { |group| required_files_group(group) }
            when :choice
              value.each { |choice| required_files_choice(choice) }
            end
          end
        end

        def required_files_elements(elements)
          elements.map do |element|
            element = @elements[element.ref_class.split(":").last] if element.key_exist?(:ref_class)
            @required_files << Utils.snake_case(element.type_name.split(':').last)
          end
        end
      end
    end
  end
end
