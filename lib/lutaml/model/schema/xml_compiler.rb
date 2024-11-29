# frozen_string_literal: true

require 'erb'
require 'lutaml/xsd'

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        extend self

        MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: '-')
          # frozen_string_literal: true

          class TempClassName < Serializable
            # Testing this Class for now
          end
        TEMPLATE

        XML_ADAPTER_NOT_SET_MESSAGE = <<~MSG
          Nokogiri is not set as XML Adapter.
          Make sure Nokogiri is installed and set as XML Adapter eg.
          execute: gem install nokogiri
          require 'lutaml/model/adapter/nokogiri'
          Lutaml::Model.xml_adapter = Lutaml::Model::Adapter::Nokogiri
        MSG

        IMPORT_CLASSES = [Xsd::Import, Xsd::Include].freeze

        SUPPORTED_DATA_TYPES = {
          nonNegativeInteger: { string: { pattern: /\+?[0-9]+/ } },
          positiveInteger: { integer: { min: 0 } },
          base64Binary: { string: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
          unsignedInt: { integer: { min: 0, max: 4294967295 } },
          hexBinary: { string: { pattern: /([0-9a-fA-F]{2})*/ } },
          dateTime: :date_time,
          boolean: :boolean,
          integer: :integer,
          string: :string,
          token: { string: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
          long: :decimal,
          int: :integer
        }.freeze

        def as_models(schema, options: {})
          unless Config.xml_adapter ||
                 Config.xml_adapter.name.end_with?('NokogiriAdapter')

            raise Error, XML_ADAPTER_NOT_SET_MESSAGE
          end

          parsed_schema = Xsd.parse(schema, location: options[:location])

          @missing_items = []
          @elements = MappingHash.new
          @attributes = MappingHash.new
          @group_types = MappingHash.new
          @simple_types = MappingHash.new
          @complex_types = MappingHash.new
          @attribute_groups = MappingHash.new

          schema_to_models([parsed_schema])
        end

        def to_models(schema, options: {})
          types = as_models(schema, options: options)

          types.to_h do |type|
            [type.file_name, MODEL_TEMPLATE.result(binding)]
          end
        end

        private

        def schema_to_models(schemas)
          return if schemas.empty?

          schemas.each do |schema|
            schema_to_models(schema.schemas) if schema.schemas.any?

            resolved_element_order(schema).each do |order_item|
              next if IMPORT_CLASSES.include?(order_item.class)

              call_missing_items
              item_name = order_item.name
              case order_item
              when Xsd::SimpleType
                @simple_types[item_name] = setup_simple_type(order_item)
              when Xsd::Group
                @group_types[item_name] = setup_group_type(order_item)
              when Xsd::ComplexType
                @complex_types[item_name] = setup_complex_type(order_item)
              when Xsd::Element
                @elements[item_name] = setup_element(order_item) if order_item.type
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
            setup_restriction(simple_type.restriction.first, hash) if simple_type&.restriction&.any?
            hash[:union] = setup_union(simple_type.union) if simple_type.union.any?
          end
        end

        def restriction_content(hash, restriction)
          hash[:max_length] = restriction.max_length.value if restriction.max_length
          min_max_values(hash, restriction) if min_and_max?(restriction)

          if valid_enumeration?(restriction)
            hash[:enumeration_values] = restriction.enumeration.map(&:value)
          end
        end

        def min_and_max?(restriction)
          restriction.min_inclusive && restriction.max_inclusive
        end

        def min_max_values(hash, restriction)
          hash[:min_value] = restriction.min_inclusive.value
          hash[:max_value] = restriction.max_inclusive.value
        end

        def valid_enumeration?(restriction)
          restriction.enumeration.is_a?(Array) &&
            restriction.enumeration.any?
        end

        def setup_complex_type(complex_type)
          MappingHash.new.tap do |hash|
            if complex_type.attribute.any?
              MappingHash.new.tap do |attr_hash|
                complex_type.attribute.each do |attribute|
                  updated_attribute = setup_attribute(attribute)
                  attr_name = attribute.name ? attribute.name : attribute.ref.split(":")&.last
                  attr_hash[attr_name] = updated_attribute.fetch(attr_name) || updated_attribute
                end
                hash[:attributes] = attr_hash
              end
            elsif complex_type.sequence.any?
              hash[:sequence] = complex_type.sequence.map do |sequence|
                setup_sequence(sequence)
              end
            elsif complex_type.choice.any?
              hash[:choice] = complex_type.choice.map { |choice| setup_choice(choice) }
            elsif complex_type.complex_content.any?
              hash[:complex_content] = setup_complex_content(complex_type.complex_content)
            end
          end
        end

        def setup_sequence(sequence)
          MappingHash.new.tap do |hash|
            resolved_element_order(sequence).each do |sequence_element|
              case sequence_element
              when Xsd::Element
                ref = sequence_element.name ? sequence_element.name : sequence_element.ref.split(":")&.last
                hash[ref] = setup_element(sequence_element)
              when Xsd::Group
                if sequence_element.name
                  hash[sequence_element.name] = @group_types[sequence_element.ref]
                else
                  ref = sequence_element.ref.split(":")&.last
                  hash[ref] = @group_types[ref]
                end
              when Xsd::Choice
                hash[:choice] = setup_choice(sequence_element)
              end
            end
          end
        end

        def validate_attr_type(type)
          stripped_type = type&.split(':')&.last
          @simple_types[stripped_type] ||
            @complex_types[stripped_type] ||
            SUPPORTED_DATA_TYPES[stripped_type&.to_sym] ||
            stripped_type&.to_sym
        end

        def setup_group_type(group)
          MappingHash.new.tap do |hash|
            if group.ref
              ref = group.ref.split(":")&.last
              if @group_types.key?(ref)
                hash[ref] = @group_types[ref]
              else
                @missing_items << proc { hash[ref] = @group_types[ref] if @group_types.key?(ref) }
              end
            else
              resolved_element_order(group).map do |element|
                case element
                when Xsd::Element
                  hash[element.name] = setup_element(element)
                when Xsd::Sequence
                  hash[:sequence] = [setup_sequence(element)]
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
                hash[:sequence] = [setup_sequence(element)]
              when Xsd::Group
                hash[:group] = setup_group_type(element)
              when Xsd::Choice
                hash[:choice] = setup_choice(element)
              end
            end
          end
        end

        def setup_union(unions)
          unions.map do |union|
            union.member_types.split.map do |member_type|
              @simple_types[member_type]
            end
          end.flatten
        end

        def setup_attribute(attribute)
          MappingHash.new.tap do |attr_hash|
            if attribute.ref
              attr_name = attribute&.ref&.split(":")&.last
              attr_hash[attr_name] = @attributes[attr_name]
            elsif attribute.type
              rest_type = validate_attr_type(attribute.type)
              if rest_type.is_a?(MappingHash)
                attr_hash.merge!(rest_type)
              else
                attr_hash[:base_class] = rest_type
              end
            end
          end
        end

        def setup_attribute_groups(attribute_group)
          MappingHash.new.tap do |hash|
            attribute_group.attribute.map do |attribute|

              if attribute.ref
                attr_name = attribute&.ref&.split(":")&.last
                hash[attr_name] = @attributes[attr_name]
              elsif attribute.type
                hash[attribute.name] = create_mapping_hash(
                  validate_attr_type(attribute.type),
                  hash_key: :base_class
                )
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
            if element.type
              hash[:class_name] = if element.type.include?(":")
                hash[:base_class] = validate_attr_type(element.type)
              else
                element.type
              end
            elsif element.ref
              ref = element.ref.split(":")&.last
              if @elements.key?(ref)
                hash.merge!(@elements[ref])
              else
                @missing_items << proc { hash.merge!(@elements[ref]) if @elements.key?(ref) }
              end
            end
            element_attrs = element_attributes(element)
            hash[:arguments] = element_attrs if element_attrs.any?
            element.complex_type.each do |complex_type|
              hash[:complex_type] = setup_complex_type(complex_type)
              @complex_types[complex_type.name] = hash[:complex_type]
            end
          end
        end

        def setup_restriction(restriction, hash)
          rest_type = validate_attr_type(restriction.base)
          if rest_type.is_a?(MappingHash)
            if restriction.pattern
              rest_type.each do |_, value|
                value[:pattern] = restriction.pattern.value
              end
            end
            hash.merge!(rest_type)
          else
            hash[:base_class] = rest_type
            hash[:pattern] = restriction.pattern.value if restriction.pattern
          end
          restriction_content(hash, restriction)
          hash[:length] = restriction.length.value if restriction.length
        end

        def setup_complex_content(complex_contents)
          MappingHash.new.tap do |hash|
            complex_contents.each do |complex_content|
              if complex_content.extension.any?
                hash[:extension] = setup_extension(complex_content.extension)
              elsif complex_content.restriction.any?
                setup_restriction(complex_content.restriction.first, hash)
              end
            end
          end
        end

        def setup_extension(extensions)
          MappingHash.new.tap do |hash|
            extensions.each do |extension|
              if extension.attribute.any?
                MappingHash.new.tap do |attr_hash|
                  extension.attribute.each do |attribute|
                    updated_attribute = setup_attribute(attribute)
                    attr_name = attribute.name ? attribute.name : attribute.ref.split(":")&.last
                    attr_hash[attr_name] = updated_attribute.fetch(attr_name) || updated_attribute
                  end
                  hash[:attributes] = attr_hash
                end
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

        def call_missing_items
          @missing_items.each_with_index do |item, item_index|
            item_called = item.call
            @missing_items.delete_at(item_index) if item_called
          end
        end

        def resolved_element_order(object, ignore_text: true)
          object.element_order.each_with_object(object.element_order.dup) do |name, array|
            next array.delete(name) if name == "text" && (ignore_text || !object.respond_to?(:text))

            index = 0
            array.each_with_index do |element, i|
              next unless element == name

              array[i] = object.send(Utils.snake_case(name))[index]
              index += 1
            end
          end
        end
      end
    end
  end
end
