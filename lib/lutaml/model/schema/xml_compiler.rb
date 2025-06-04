# frozen_string_literal: true

require "erb"
require "tmpdir"
require "lutaml/xsd"
require_relative "xml_compiler/attribute_group"
require_relative "xml_compiler/simple_content"
require_relative "xml_compiler/complex_type"
require_relative "xml_compiler/restriction"
require_relative "xml_compiler/simple_type"
require_relative "xml_compiler/attribute"
require_relative "xml_compiler/sequence"
require_relative "xml_compiler/element"
require_relative "xml_compiler/choice"
require_relative "xml_compiler/group"

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        extend self

        attr_reader :simple_types,
                    :group_types,
                    :complex_types,
                    :elements,
                    :attributes,
                    :attribute_groups

        ELEMENT_ORDER_IGNORABLE = %w[import include].freeze

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
          @simple_types.merge!(XmlCompiler::SimpleType.setup_supported_types)
          classes_list = @simple_types.merge(@complex_types).merge(@group_types)
          classes_list = classes_list.to_h { |name, type| [Utils.camel_case(name), type.to_class] }
          if options[:create_files]
            dir = options.fetch(:output_dir, "lutaml_models_#{Time.now.to_i}")
            FileUtils.mkdir_p(dir)
            classes_list.each { |name, klass| create_file(name, klass, dir) }
            nil
          else
            require_classes(classes_list) if options[:load_classes]
            classes_list
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
                @group_types[item_name] = setup_group_type(order_item, root_call: true)
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
          SimpleType.new(simple_type.name).tap do |type_object|
            if union = simple_type.union
              type_object.instance = union.member_types.split.map { |member_type| @simple_types[member_type] }.flatten
            elsif restriction = simple_type.restriction
              type_object.base_class = restriction.base&.split(":")&.last
              type_object.instance = setup_restriction(restriction)
            end
          end
        end

        def restriction_content(instance, restriction)
          return instance unless restriction.respond_to?(:max_length)

          restriction_min_max(restriction, instance, field: :max_length, value_method: :min)
          restriction_min_max(restriction, instance, field: :min_length, value_method: :max)
          restriction_min_max(restriction, instance, field: :min_inclusive, value_method: :max)
          restriction_min_max(restriction, instance, field: :max_inclusive, value_method: :min)
          restriction_min_max(restriction, instance, field: :max_exclusive, value_method: :max)
          restriction_min_max(restriction, instance, field: :min_exclusive, value_method: :min)
          instance.length = restriction_length(restriction.length) if restriction.length&.any?
        end

        # Use min/max to get the value from the field_value array.
        def restriction_min_max(restriction, instance, field:, value_method: :min)
          field_value = restriction.public_send(field)
          return unless field_value&.any?

          instance.public_send(
            :"#{field}=",
            field_value.map(&:value).send(value_method).to_s,
          )
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
          ComplexType.new.tap do |instance|
            instance.id = complex_type.id
            instance.name = complex_type.name
            instance.mixed = complex_type.mixed
            resolved_element_order(complex_type).each do |element|
              case element
              when Xsd::Attribute
                instance << setup_attribute(element)
              when Xsd::Sequence
                instance << setup_sequence(element)
              when Xsd::Choice
                instance << setup_choice(element)
              when Xsd::ComplexContent
                instance << setup_complex_content(element, instance.name)
              when Xsd::AttributeGroup
                instance << setup_attribute_groups(element)
              when Xsd::Group
                instance << setup_group_type(element)
              when Xsd::SimpleContent
                instance.simple_content = setup_simple_content(element)
              end
            end
          end
        end

        def setup_simple_content(simple_content)
          SimpleContent.new.tap do |instance|
            if simple_content.extension
              instance.base_class = simple_content.extension.base
              setup_extension(simple_content.extension, instance)
            elsif simple_content.restriction
              instance.base_class = simple_content.restriction.base
              instance << setup_restriction(simple_content.restriction)
            end
          end
        end

        def setup_sequence(sequence)
          Sequence.new.tap do |instance|
            resolved_element_order(sequence).each do |object|
              case object
              when Xsd::Sequence
                instance << setup_sequence(object)
              when Xsd::Element
                instance << setup_element(object)
              when Xsd::Choice
                instance << setup_choice(object)
              when Xsd::Group
                instance << setup_group_type(object)
              when Xsd::Any
                # No implementation yet!
              end
            end
          end
        end

        def setup_group_type(group, root_call: false)
          object = Group.new(group.name, group.ref)
          object.instance = setup_group_type_instance(group)
          @group_types[group.name] = object if group.name && !root_call
          object
        end

        def setup_group_type_instance(group)
          if sequence = group.sequence
            setup_sequence(group.sequence)
          elsif choice = group.choice
            setup_choice(group.choice)
          end
        end

        def setup_choice(choice)
          Choice.new.tap do |instance|
            instance.min_occurs = choice.min_occurs
            instance.max_occurs = choice.max_occurs
            resolved_element_order(choice).each do |element|
              case element
              when Xsd::Element
                instance << setup_element(element)
              when Xsd::Sequence
                instance << setup_sequence(element)
              when Xsd::Group
                instance << setup_group_type(element)
              when Xsd::Choice
                instance << setup_choice(element)
              end
            end
          end
        end

        def setup_attribute(attribute)
          instance = Attribute.new(name: attribute.name, ref: attribute.ref)
          if attribute.name
            instance.type = setup_attribute_type(attribute)
            instance.default = attribute.default
          end
          instance
        end

        def setup_attribute_type(attribute)
          return attribute.type if attribute.type

          simple_type = attribute.simple_type
          attr_name = attribute.name
          simple_type.name = attr_name
          @simple_types[attr_name] = setup_simple_type(simple_type)
          attr_name
        end

        def setup_attribute_groups(attribute_group)
        instance = AttributeGroup.new(name: attribute_group.name, ref: attribute_group.ref)
          if attribute_group.name
            instance.attributes = [] if attribute_group.attribute&.any?
            instance.attribute_groups = [] if attribute_group.attribute_group&.any?
            resolved_element_order(attribute_group).each do |object|
              case object
              when Xsd::Attribute
                instance.attributes << setup_attribute(object)
              when Xsd::AttributeGroup
                instance.attribute_groups << setup_attribute_groups(object)
              end
            end
          end
          instance
        end

        def create_mapping_hash(value, hash_key: :class_name)
          MappingHash.new.tap do |hash|
            hash[hash_key] = value
          end
        end

        def setup_element(element)
          element_name = element.name
          instance = Element.new(name: element_name, ref: element.ref)
          if element_name
            instance.min_occurs = element.min_occurs
            instance.max_occurs = element.max_occurs
            instance.type = setup_element_type(element, instance)
            instance.id = element.id
            instance.fixed = element.fixed
            instance.default = element.default
          end
          instance
        end

        # Populates @simple_types or @complex_types based on elements available value.
        def setup_element_type(element, instance)
          return element.type if element.type

          type = element.simple_type ? "simple" : "complex"
          type_instance = element.public_send(:"#{type}_type")
          type_instance.name = element.name
          instance_variable_get(:"@#{type}_types")[element.name] = public_send(:"setup_#{type}_type", type_instance)
          type_instance.name
        end

        def setup_restriction(restriction)
          Restriction.new.tap do |instance|
            instance.base_class = restriction.base
            restriction_patterns(restriction.pattern, instance) if restriction.respond_to?(:pattern)
            restriction_content(instance, restriction)
            if restriction.respond_to?(:enumeration) && restriction.enumeration&.any?
              instance.enumerations = restriction.enumeration.map(&:value)
            end
          end
        end

        def restriction_patterns(patterns, instance)
          return if Utils.blank?(patterns)

          instance.pattern = patterns.map { |p| "(#{p.value})" }.join("|")
        end

        def setup_complex_content(complex_content, name)
          @complex_types[name] = ComplexType.new.tap do |instance|
            instance.mixed = true if complex_content.mixed
            instance.instances << if extension = complex_content.extension
                                  instance.base_class = extension.base
                                  setup_extension(complex_content.extension, instance)
                                elsif restriction = complex_content.restriction
                                  instance.base_class = restriction.base
                                  setup_restriction(restriction)
                                end
          end
        end

        def setup_extension(extension, instance)
          instance.base_class = extension.base
          resolved_element_order(extension).each do |element|
            case element
            when Xsd::Attribute
              instance << setup_attribute(element)
            when Xsd::AttributeGroup
              instance << setup_attribute_groups(element)
            when Xsd::Sequence
              instance << setup_sequence(element)
            when Xsd::Choice
              instance << setup_choice(element)
            when Xsd::Group
              instance << setup_group_type(element)
            end
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
      end
    end
  end
end
