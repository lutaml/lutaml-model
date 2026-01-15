# frozen_string_literal: true

require "erb"
require "tmpdir"
require "lutaml/xsd"
require_relative "xml_compiler/complex_content_restriction"
require_relative "xml_compiler/attribute_group"
require_relative "xml_compiler/complex_content"
require_relative "xml_compiler/simple_content"
require_relative "xml_compiler/complex_type"
require_relative "xml_compiler/restriction"
require_relative "xml_compiler/simple_type"
require_relative "xml_compiler/attribute"
require_relative "xml_compiler/sequence"
require_relative "xml_compiler/element"
require_relative "xml_compiler/choice"
require_relative "xml_compiler/group"
require_relative "xml_compiler/xml_namespace_class"
require_relative "xml_compiler/registry_generator"

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
                    :attribute_groups,
                    :namespace_classes

        ELEMENT_ORDER_IGNORABLE = %w[import include].freeze

        XML_ADAPTER_NOT_SET_MESSAGE = <<~MSG
          Nokogiri is not set as XML Adapter.
          Make sure Nokogiri is installed and set as XML Adapter eg.
          execute: gem install nokogiri
          require 'lutaml/model/adapter/nokogiri'
          Lutaml::Model.xml_adapter = Lutaml::Model::Adapter::Nokogiri
        MSG

        XML_DEFINED_ATTRIBUTES = {
          "id" => "Lutaml::Model::Xml::W3c::XmlIdType",
          "lang" => "Lutaml::Model::Xml::W3c::XmlLangType",
          "space" => "Lutaml::Model::Xml::W3c::XmlSpaceType",
          "base" => "Lutaml::Model::Xml::W3c::XmlBaseType",
        }.freeze

        def to_models(schema, options = {})
          as_models(schema, options: options)
          options[:indent] = options[:indent] ? options[:indent].to_i : 2

          # Auto-generate module namespace from output directory if not explicitly set
          unless options.key?(:module_namespace)
            output_dir = options.fetch(:output_dir, "lutaml_models_#{Time.now.to_i}")
            # Generate a namespace from the directory name (e.g., "my_models" -> "MyModels")
            dir_name = File.basename(output_dir).split('_').map(&:capitalize).join
            options[:module_namespace] = dir_name
          end

          # Allow explicit nil to disable namespace
          # only set default register_id if module_namespace is present
          if options[:module_namespace]
            options[:register_id] ||= :default
          end

          @simple_types.merge!(XmlCompiler::SimpleType.setup_supported_types)

          # Generate namespace classes
          namespace_classes_hash = {}
          @namespace_classes.each do |name, ns_class|
            namespace_classes_hash[name] = ns_class.to_class
          end

          classes_list = namespace_classes_hash.merge(@simple_types).merge(@complex_types).merge(@group_types)
          classes_list = classes_list.transform_values do |type|
            # Skip namespace classes (already strings) and only process model types
            next type if type.is_a?(String)
            type.to_class(options: options.merge(
              module_namespace: options[:module_namespace],
              register_id: options[:register_id]
            ))
          end
          if options[:create_files]
            dir = options.fetch(:output_dir, "lutaml_models_#{Time.now.to_i}")

            # If module_namespace provided, create subdirectories
            if options[:module_namespace]
              module_path = options[:module_namespace].split("::").map(&:downcase).join("/")
              full_dir = File.join(dir, module_path)
              FileUtils.mkdir_p(full_dir)

              # Generate central registry file
              registry_content = RegistryGenerator.generate(classes_list, options)
              if registry_content
                # Registry file goes in parent directory of module path
                registry_name = module_path.split("/").last
                registry_file = File.join(dir, "#{registry_name}_registry.rb")
                File.write(registry_file, registry_content)
              end

              # Write class files
              classes_list.each { |name, klass| create_file(name, klass, full_dir) }
            else
              FileUtils.mkdir_p(dir)
              classes_list.each { |name, klass| create_file(name, klass, dir) }
            end
            true
          else
            require_classes(classes_list) if options[:load_classes]
            classes_list
          end
        end

        def create_file(name, content, dir)
          name = name.split(":").last
          File.write("#{dir}/#{Utils.snake_case(name)}.rb", content)
        end

        def require_classes(classes_hash)
          Dir.mktmpdir do |dir|
            classes_hash.each { |name, klass| create_file(name, klass, dir) }
            # Some files are not created at the time of the require, so we need to require them after all the files are created.
            classes_hash.each_key do |name|
              require "#{dir}/#{Utils.snake_case(name)}"
            end
          end
        end

        def as_models(schema, options: {})
          unless Config.xml_adapter.name.end_with?("NokogiriAdapter")
            raise Error,
                  XML_ADAPTER_NOT_SET_MESSAGE
          end

          parsed_schema = Xsd.parse(schema, location: options[:location])

          @elements = MappingHash.new
          @attributes = MappingHash.new
          @group_types = MappingHash.new
          @simple_types = MappingHash.new
          @complex_types = MappingHash.new
          @attribute_groups = MappingHash.new
          @namespace_classes = MappingHash.new

          populate_default_values
          collect_namespaces(Array(parsed_schema), options)
          schema_to_models(Array(parsed_schema))
        end

        def populate_default_values
          XML_DEFINED_ATTRIBUTES.each do |name, value|
            @attributes[name] = Attribute.new(name: name)
            @attributes[name].type = value
          end

          # W3C XmlNamespace is now auto-loaded via lutaml/model.rb
          # Reference: Lutaml::Model::Xml::W3c::XmlNamespace
        end

        def schema_to_models(schemas)
          return if schemas.empty?

          schemas.each do |schema|
            schema_to_models(schema.include) if schema.include&.any?
            schema_to_models(schema.import) if schema.import&.any?
            resolved_element_order(schema).each do |order_item|
              item_name = order_item.name if order_item.respond_to?(:name)
              case order_item
              when Xsd::SimpleType
                @simple_types[item_name] = setup_simple_type(order_item)
              when Xsd::Group
                @group_types[item_name] =
                  setup_group_type(order_item, root_call: true)
              when Xsd::ComplexType
                @complex_types[item_name] = setup_complex_type(order_item)
              when Xsd::Element
                @elements[item_name] = setup_element(order_item)
              when Xsd::Attribute
                @attributes[item_name] = setup_attribute(order_item)
              when Xsd::AttributeGroup
                @attribute_groups[item_name] =
                  setup_attribute_groups(order_item)
              end
            end
          end
          nil
        end

        def setup_simple_type(simple_type)
          SimpleType.new(simple_type.name).tap do |type_object|
            if union = simple_type.union
              type_object.unions = union.member_types.split
            elsif restriction = simple_type.restriction
              type_object.base_class = restriction.base&.split(":")&.last
              type_object.instance = setup_restriction(restriction)
            end
          end
        end

        def restriction_content(instance, restriction)
          return instance unless restriction.respond_to?(:max_length)

          restriction_min_max(restriction, instance, field: :max_length,
                                                     value_method: :min)
          restriction_min_max(restriction, instance, field: :min_length,
                                                     value_method: :max)
          restriction_min_max(restriction, instance, field: :min_inclusive,
                                                     value_method: :max)
          restriction_min_max(restriction, instance, field: :max_inclusive,
                                                     value_method: :min)
          restriction_min_max(restriction, instance, field: :max_exclusive,
                                                     value_method: :max)
          restriction_min_max(restriction, instance, field: :min_exclusive,
                                                     value_method: :min)
          instance.length = restriction_length(restriction.length) if restriction.length&.any?
        end

        # Use min/max to get the value from the field_value array.
        def restriction_min_max(restriction, instance, field:,
value_method: :min)
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
                instance << setup_complex_content(element, instance.name,
                                                  instance)
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
              # No implementation yet for Xsd::Any!
              next if object.is_a?(Xsd::Any)

              instance << case object
                          when Xsd::Sequence
                            setup_sequence(object)
                          when Xsd::Element
                            setup_element(object)
                          when Xsd::Choice
                            setup_choice(object)
                          when Xsd::Group
                            setup_group_type(object)
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
            setup_sequence(sequence)
          elsif choice = group.choice
            setup_choice(choice)
          end
        end

        def setup_choice(choice)
          Choice.new.tap do |instance|
            instance.min_occurs = choice.min_occurs
            instance.max_occurs = choice.max_occurs
            resolved_element_order(choice).each do |element|
              instance << case element
                          when Xsd::Element
                            setup_element(element)
                          when Xsd::Sequence
                            setup_sequence(element)
                          when Xsd::Group
                            setup_group_type(element)
                          when Xsd::Choice
                            setup_choice(element)
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
          attr_name = "ST_#{attribute.name}"
          simple_type.name = attr_name
          @simple_types[attr_name] = setup_simple_type(simple_type)
          attr_name
        end

        def setup_attribute_groups(attribute_group)
          instance = AttributeGroup.new(name: attribute_group.name,
                                        ref: attribute_group.ref)
          if attribute_group.name
            resolved_element_order(attribute_group).each do |object|
              group_attribute = case object
                                when Xsd::Attribute
                                  setup_attribute(object)
                                when Xsd::AttributeGroup
                                  setup_attribute_groups(object)
                                end
              instance << group_attribute if group_attribute
            end
          end
          instance
        end

        def setup_element(element)
          element_name = element.name
          instance = Element.new(name: element_name, ref: element.ref)
          instance.min_occurs = element.min_occurs
          instance.max_occurs = element.max_occurs
          if element_name
            instance.type = setup_element_type(element, instance)
            instance.id = element.id
            instance.fixed = element.fixed
            instance.default = element.default
          end
          instance
        end

        # Populates @simple_types or @complex_types based on elements available value.
        def setup_element_type(element, _instance)
          return element.type if element.type

          type, prefix = if element.simple_type
                           ["simple",
                            "ST"]
                         else
                           ["complex", "CT"]
                         end
          type_instance = element.public_send(:"#{type}_type")
          type_instance.name = [prefix, element.name].join("_")
          instance_variable_get(:"@#{type}_types")[type_instance.name] =
            public_send(:"setup_#{type}_type", type_instance)
          type_instance.name
        end

        def setup_restriction(restriction)
          Restriction.new.tap do |instance|
            instance.base_class = restriction.base
            if restriction.respond_to?(:pattern)
              restriction_patterns(restriction.pattern,
                                   instance)
            end
            restriction_content(instance, restriction)
            if restriction.respond_to?(:enumeration) && restriction.enumeration&.any?
              instance.enumerations = restriction.enumeration.map(&:value)
            end
          end
        end

        def setup_complex_content_restriction(restriction,
compiler_complex_type)
          ComplexContentRestriction.new.tap do |instance|
            compiler_complex_type.base_class = restriction.base
            resolved_element_order(restriction).each do |element|
              instance << case element
                          when Xsd::Attribute
                            setup_attribute(element)
                          when Xsd::AttributeGroup
                            setup_attribute_groups(element)
                          when Xsd::Sequence
                            setup_sequence(element)
                          when Xsd::Choice
                            setup_choice(element)
                          when Xsd::Group
                            setup_group_type(element)
                          end
            end
          end
        end

        def restriction_patterns(patterns, instance)
          return if Utils.blank?(patterns)

          instance.pattern = patterns.map { |p| "(#{p.value})" }.join("|")
        end

        def setup_complex_content(complex_content, name, compiler_complex_type)
          @complex_types[name] = ComplexContent.new.tap do |instance|
            compiler_complex_type.mixed = complex_content.mixed
            if extension = complex_content.extension
              setup_extension(extension, compiler_complex_type)
            elsif restriction = complex_content.restriction
              instance.restriction = setup_complex_content_restriction(restriction, compiler_complex_type)
            end
          end
        end

        def setup_extension(extension, instance)
          instance.base_class = extension.base
          resolved_element_order(extension).each do |element|
            instance << case element
                        when Xsd::Attribute
                          setup_attribute(element)
                        when Xsd::AttributeGroup
                          setup_attribute_groups(element)
                        when Xsd::Sequence
                          setup_sequence(element)
                        when Xsd::Choice
                          setup_choice(element)
                        when Xsd::Group
                          setup_group_type(element)
                        end
          end
        end

        def resolved_element_order(object)
          return [] if object.element_order.nil?

          object.element_order.each_with_object(object.element_order.dup) do |builder_instance, array|
            next array.delete(builder_instance) if builder_instance.text? || ELEMENT_ORDER_IGNORABLE.include?(builder_instance.name)

            index = 0
            array.each_with_index do |element, i|
              next unless element == builder_instance

              array[i] =
                Array(object.send(Utils.snake_case(builder_instance.name)))[index]
              index += 1
            end
          end
        end

        def collect_namespaces(schemas, options)
          # Collect unique namespace URIs from the schemas
          namespace_uris = Set.new

          # Add the main namespace from options if provided
          if options[:namespace]
            namespace_uris.add(options[:namespace])
          end

          # Extract namespaces from schema elements
          schemas.each do |schema|
            namespace_uris.add(schema.target_namespace) if schema.target_namespace
          end

          # Create XmlNamespaceClass for each unique namespace
          namespace_uris.each do |uri|
            next if uri.nil? || uri.empty?

            # Use provided prefix if available
            prefix = options[:prefix] if options[:namespace] == uri

            ns_class = XmlNamespaceClass.new(uri: uri, prefix: prefix)
            @namespace_classes[ns_class.class_name] = ns_class
          end
        end
      end
    end
  end
end
