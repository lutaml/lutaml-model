# frozen_string_literal: true

module Lutaml
  module Xml
    module Serialization
      # XML-specific format conversion hooks for Serialize module
      #
      # This module provides XML-specific serialization logic that extends
      # the format-agnostic Lutaml::Model::Serialize::FormatConversion.
      #
      # It is prepended into Serialize::ClassMethods when XML format is loaded,
      # overriding the hook methods defined in FormatConversion.
      module FormatConversion
        # Class-level namespace directive for XML.
        #
        # @deprecated Use namespace inside `xml do ... end` blocks instead.
        #
        # @param ns_class [Class, nil] XmlNamespace class to associate with this model
        # @return [Class, nil] the XmlNamespace class
        def namespace(ns_class = nil)
          if ns_class
            unless ns_class.is_a?(Class) && ns_class < Lutaml::Xml::Namespace
              raise ArgumentError,
                    "namespace must be an XmlNamespace class, got #{ns_class.class}"
            end

            warn_class_level_namespace_usage(ns_class)
            @namespace_class = ns_class
          end
          @namespace_class
        end

        # Get the namespace URI for this Model
        #
        # @return [String, nil] the namespace URI
        def namespace_uri
          @namespace_class&.uri
        end

        # Get the default namespace prefix for this Model
        #
        # @return [String, nil] the namespace prefix
        def namespace_prefix
          @namespace_class&.prefix_default
        end

        # Override choice to set format: :xml so Choice knows which format it belongs to.
        def choice(min: 1, max: 1, format: :xml, &)
          super
        end

        # Override process_mapping for XML format to handle mapping class inheritance.
        #
        # When `xml SomeMapping` is called with a mapping class argument,
        # inherits mappings from the class instead of using a DSL block.
        #
        # @param format [Symbol] The format
        # @param args [Array] Additional arguments (mapping class for XML)
        # @param block [Proc] The DSL block
        def process_mapping(format, *args, &)
          if format == :xml && args.any? && args.first.is_a?(Class) && args.first < Lutaml::Xml::Mapping
            process_xml_mapping_class_inheritance(args.first, &)
          else
            super
          end
        end

        # XML-specific post-processing after mapping DSL evaluation
        #
        # @param format [Symbol] The format
        def post_process_mapping(format)
          return super unless format == :xml

          check_sort_configs!
        end

        # XML-specific pre-deserialization: resolve XML mapping imports
        #
        # @param format [Symbol] The format
        # @param register [Symbol] The register
        def pre_deserialize_hook(format, register)
          return super unless format == :xml

          mappings[:xml]&.ensure_mappings_imported!(register)
        end

        # XML-specific document validation: root mapping, encoding, doctype
        #
        # @param format [Symbol] The format
        # @param doc [Object] The parsed document
        # @param options [Hash] Options hash (modified in place)
        # @param register [Symbol] The register
        def validate_document(format, doc, options, register)
          return super unless format == :xml

          valid = root?(register) || options[:from_collection]
          raise Lutaml::Model::NoRootMappingError.new(self) unless valid

          options[:encoding] = doc.encoding
          if doc.respond_to?(:doctype) && doc.doctype
            options[:doctype] = doc.doctype
          end
        end

        # XML-specific options preparation for serialization
        #
        # @param format [Symbol] The format
        # @param instance [Object] The model instance
        # @param options [Hash] The options hash
        # @return [Hash] The modified options hash
        def prepare_to_options(format, instance, options)
          return super unless format == :xml

          options[:mapper_class] = self

          # Handle prefix option for XML
          if options.key?(:prefix)
            prefix_option = options[:prefix]
            mappings_for(:xml)

            case prefix_option
            when true
              options[:use_prefix] = true
            when String
              options[:use_prefix] = prefix_option
            when false, :default, nil
              options[:use_prefix] = false
            end
            options.delete(:prefix)
          end

          # Apply namespace prefix overrides for XML format
          if options[:namespaces]
            options = apply_namespace_overrides(options)
          end

          # Retrieve stored declaration plan from model instance for namespace preservation
          if instance.is_a?(Lutaml::Model::Serialize) &&
              !options.key?(:stored_xml_declaration_plan)
            stored_plan = instance.import_declaration_plan
            options[:stored_xml_declaration_plan] = stored_plan if stored_plan
          end

          options
        end

        # XML-specific pre-serialization: resolve XML mapping imports
        #
        # @param format [Symbol] The format
        # @param register [Symbol] The register
        def pre_serialize_hook(format, register)
          return super unless format == :xml

          mappings[:xml]&.ensure_mappings_imported!(register)
        end

        # Add XML-specific model methods (ordered, mixed, element_order, etc.)
        # when `model CustomClass` is used with a plain Ruby class.
        #
        # @param klass [Class] The model class
        def add_format_specific_model_methods(klass)
          super
          Lutaml::Model::Utils.add_boolean_accessor_if_not_defined(klass,
                                                                   :ordered)
          Lutaml::Model::Utils.add_boolean_accessor_if_not_defined(klass,
                                                                   :mixed)
          Lutaml::Model::Utils.add_accessor_if_not_defined(klass,
                                                           :element_order)
          Lutaml::Model::Utils.add_accessor_if_not_defined(klass, :encoding)
          Lutaml::Model::Utils.add_accessor_if_not_defined(klass, :doctype)
          # XML namespace metadata accessors for custom model classes
          %i[xml_namespace_prefix xml_ns_prefixes original_namespace_uri
             xml_declaration raw_schema_location].each do |attr|
            Lutaml::Model::Utils.add_accessor_if_not_defined(klass, attr)
          end
        end

        # Apply namespace prefix overrides for XML serialization
        #
        # @param options [Hash] The options hash
        # @return [Hash] The modified options hash
        def apply_namespace_overrides(options)
          namespaces = options[:namespaces]
          return options unless namespaces.is_a?(Array)

          # Build a namespace URI to prefix mapping
          ns_prefix_map = {}
          namespaces.each do |ns_config|
            if ns_config.is_a?(Hash)
              ns_class = ns_config[:namespace]
              prefix = ns_config[:prefix]

              if ns_class.is_a?(Class) && ns_class < Lutaml::Xml::Namespace && prefix
                ns_prefix_map[ns_class.uri] = prefix.to_s
              end
            end
          end

          unless ns_prefix_map.empty?
            options[:namespace_prefix_map] = ns_prefix_map
          end
          options
        end

        private

        # Handle XML mapping class inheritance pattern (e.g., `xml SomeMapping`)
        #
        # When a mapping class is passed, inherit mappings from it directly.
        # This supports the reusable mapping class pattern.
        #
        # @param mapping_class [Class] The XML mapping class to inherit from
        # @param block [Proc] Optional additional DSL block
        def process_xml_mapping_class_inheritance(mapping_class, &block)
          # Start with a copy of the parent class's XML mapping (if any).
          parent_class = superclass_with_xml_mapping(self)
          parent_xml_mapping = if parent_class.respond_to?(:mappings)
                                 parent_class.mappings[:xml]
                               end
          @xml_mapping = if parent_xml_mapping
                           parent_xml_mapping.deep_dup
                         else
                           Lutaml::Xml::Mapping.new
                         end

          # Get the parent mapping instance (DSL already evaluated via xml_mapping_instance)
          parent_mapping = if mapping_class.respond_to?(:xml_mapping_instance) &&
              mapping_class.xml_mapping_instance
                             mapping_class.xml_mapping_instance
                           else
                             mapping_class.new
                           end

          # --- Inherit namespaces ---
          inherit_xml_namespaces(parent_mapping)

          # --- Inherit element mappings ---
          inherit_xml_elements(parent_mapping)

          # --- Inherit attribute mappings ---
          inherit_xml_attributes(parent_mapping)

          # --- Inherit element/root configuration ---
          inherit_xml_configuration(parent_mapping, mapping_class)

          # Evaluate any additional block
          @xml_mapping.instance_eval(&block) if block

          # Store in mappings[:xml] so the transformer can find it.
          mappings[:xml] = @xml_mapping

          @xml_mapping
        end

        # Find the nearest superclass that has an XML mapping.
        #
        # @param klass [Class] The starting class
        # @return [Class, nil] The superclass with XML mapping or nil
        def superclass_with_xml_mapping(klass)
          return nil unless klass.is_a?(Class)

          parent = klass.superclass
          return nil unless parent < Lutaml::Model::Serializable

          parent_mapping = parent.mappings[:xml] if parent.respond_to?(:mappings)
          return parent if parent_mapping

          superclass_with_xml_mapping(parent)
        end

        def inherit_xml_namespaces(parent_mapping)
          existing_ns = @xml_mapping.namespace_scope || []
          parent_ns = parent_mapping.namespace_scope || []
          all_ns = (existing_ns + parent_ns).uniq
          @xml_mapping.namespace_scope(all_ns) if all_ns.any?

          if parent_mapping.respond_to?(:namespace_scope_config) &&
              (parent_ns_config = parent_mapping.namespace_scope_config) &&
              parent_ns_config.any?
            existing_ns_config = @xml_mapping.namespace_scope_config || []
            merged_ns_config = (existing_ns_config + parent_ns_config).uniq
            @xml_mapping.namespace_scope_config = merged_ns_config
          end
        end

        def inherit_xml_elements(parent_mapping)
          parent_mapping.mapping_elements_hash.each do |key, rule|
            existing = @xml_mapping.elements_hash[key]
            if existing.nil?
              @xml_mapping.elements_hash[key] =
                rule.deep_dup
            elsif existing.is_a?(Array) && rule.is_a?(Array)
              merged = existing + rule.reject do |r|
                existing.any? do |e|
                  e.eql?(r)
                end
              end
              @xml_mapping.elements_hash[key] = merged
            elsif existing.is_a?(Array)
              existing << rule.deep_dup unless existing.any? do |e|
                e.eql?(rule)
              end
            elsif rule.is_a?(Array)
              unless rule.any? { |r| r.eql?(existing) }
                @xml_mapping.elements_hash[key] =
                  [existing, *rule]
              end
            elsif !existing.eql?(rule)
              @xml_mapping.elements_hash[key] =
                [existing, rule.deep_dup]
            end
          end
        end

        def inherit_xml_attributes(parent_mapping)
          parent_mapping.mapping_attributes_hash.each do |key, rule|
            existing = @xml_mapping.attributes_hash[key]
            if existing.nil?
              @xml_mapping.attributes_hash[key] =
                rule.deep_dup
            elsif existing.is_a?(Array) && rule.is_a?(Array)
              merged = existing + rule.reject do |r|
                existing.any? do |e|
                  e.eql?(r)
                end
              end
              @xml_mapping.attributes_hash[key] = merged
            elsif existing.is_a?(Array)
              existing << rule.deep_dup unless existing.any? do |e|
                e.eql?(rule)
              end
            elsif rule.is_a?(Array)
              unless rule.any? { |r| r.eql?(existing) }
                @xml_mapping.attributes_hash[key] =
                  [existing, *rule]
              end
            elsif !existing.eql?(rule)
              @xml_mapping.attributes_hash[key] =
                [existing, rule.deep_dup]
            end
          end
        end

        def inherit_xml_configuration(parent_mapping, mapping_class)
          if parent_mapping.element_name && !@xml_mapping.element_name
            @xml_mapping.element(parent_mapping.element_name)
          end

          if parent_mapping.namespace_class &&
              !@xml_mapping.namespace_class?
            @xml_mapping.namespace(parent_mapping.namespace_class)
          end

          if parent_mapping.namespace_param == :inherit &&
              !@xml_mapping.namespace_set?
            @xml_mapping.namespace(:inherit)
          end

          @xml_mapping.inherit_from(mapping_class)
        end

        # Issue deprecation warning for class-level namespace usage
        #
        # @param ns_class [Class] The namespace class
        def warn_class_level_namespace_usage(ns_class)
          return if @namespace_warning_issued

          warn <<~WARNING
            [Lutaml::Model] DEPRECATION WARNING: Class-level `namespace` directive is deprecated for Serializable classes.
            Class: #{name}
            Namespace: #{ns_class.name} (#{ns_class.uri})

            The class-level namespace directive does NOT apply namespace prefixes during serialization.

            INCORRECT (current usage):
              class #{name} < Lutaml::Model::Serializable
                namespace #{ns_class.name}  # Does nothing!
            #{'    '}
                xml do
                  element "element"
                  map_element "field", to: :field
                end
              end

            CORRECT (use namespace inside xml block):
              class #{name} < Lutaml::Model::Serializable
                xml do
                  element "element"
                  namespace #{ns_class.name}  # Works correctly!
                  map_element "field", to: :field
                end
              end

            This warning will become an error in the next major release.
          WARNING

          @namespace_warning_issued = true
        end
      end
    end
  end
end
