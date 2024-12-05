# frozen_string_literal: true

require 'erb'
require 'lutaml/xsd'
require_relative 'templates/simple_type'

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        extend self

        MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: '-')
          # frozen_string_literal: true

          class <%= Utils.camel_case(name) -%> < Lutaml::Model::Serialize
            <% if content.key_exist?(:attributes) && content.attributes.any? -%>
              <% content.attributes.each do |attribute_name, attribute| -%>
                <% attribute = @attributes[attribute.ref_class.split(':')&.last] if attribute.key_exist?(:ref_class) -%>
                attribute :<%= Utils.snake_case(attribute_name) -%>, <%= Utils.camel_case(attribute.base_class) -%>
              <% end -%>
            <% end -%>
            <% if content.key_exist?(:sequence) && content.sequence.any? -%>
              <% content.sequence.each do |sequence| -%>
                sequence do
                  <% sequence.elements.each do |element| -%>
                    <% element = @elements[element.ref_class.split(':')&.last] if element.key_exist?(:ref_class) -%>
                    attribute :<%= Utils.snake_case(element.element_name) -%>, <%= Utils.camel_case(element.type_name) -%>
                  <% end -%>
                  <% sequence.groups.each do |group| -%>
                    group do
                      <% group = @group_types[group.ref_class.split(":").last] if group.key_exist?(:ref_class) -%>
                      <% group.each do |type, type_value| -%>
                        <%= type -%> do
                          <% if type == :sequence -%>
                            <% type_value.each do |sequence| -%>
                              <% binding.irb -%>
                            <% end -%>
                          <% elsif type == :choice -%>
                            <% type_value.each do |choice, choice_value|-%>
                              attribute :<%= choice -%>, <%= Utils.camel_case(choice_value.type_name) -%>
                            <% end -%>
                          <% end -%>
                        end
                      <% end -%>
                    end
                  <% end -%>
                end
              <% end -%>
            <% end -%>
            <% if content.key_exist?(:attributes) && content.attributes.any? -%>
              <% content.attributes.each do |attribute_name, attribute| -%>
                <% attribute = @attributes[attribute.ref_class.split(':')&.last] if attribute.key_exist?(:ref_class) -%>
                attribute :<%= Utils.snake_case(attribute_name) -%>, <%= Utils.camel_case(attribute.base_class) -%>
              <% end -%>
            <% end -%>
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

          Templates::SimpleType.create_simple_types(@simple_types)
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
          hash[:min_inclusive] = restriction.min_inclusive.map(&:value).min if restriction.max_length&.any?
          hash[:max_inclusive] = restriction.max_inclusive.map(&:value).max if restriction.min_length&.any?
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
            elsif attribute.type
              rest_type = attribute.type
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
                when Xsd::AnyAttribute
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
            if complex_content.extension
              hash[:extension] = setup_extension(complex_content.extension)
            elsif restriction = complex_content.restriction
              setup_restriction(restriction, hash)
            end
          end
        end

        def setup_extension(extension)
          MappingHash.new.tap do |hash|
            hash[:attribute_groups] = [] if extension&.attribute_group&.any?
            hash[:attributes] = [] if extension&.attribute&.any?
            resolved_element_order(extension).each do |element|
              case element
              when Xsd::AttributeGroup
                binding.irb
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

        def resolve_type(type)
          @simple_types[type] ||
            @complex_types[type] ||
            type.to_sym
        end
      end
    end
  end
end
