# frozen_string_literal: true

module Lutaml
  module Xml
    module Adapter
      # Shared XML serialization logic for all adapters
      #
      # This module provides the common three-phase XML serialization architecture:
      # 1. Collect namespace needs from XmlElement tree
      # 2. Plan namespace declarations with hoisting
      # 3. Render using parallel traversal (XmlElement + DeclarationPlan)
      #
      # All adapters follow the same pattern:
      # - Case A: Parsed element (adapter-specific) → build_xml
      # - Case B: XmlElement → build_xml_element_with_plan
      # - Case C: Model instance → transform to XmlElement OR legacy path
      #
      # @example Include in adapter
      #   class NokogiriAdapter < BaseAdapter
      #     include XmlSerialization
      #
      #     private
      #
      #     def build_xml_element_with_plan(xml, xml_element, plan, options)
      #       # Adapter-specific implementation
      #     end
      #   end
      module XmlSerialization
        # Serialize to XML using three-phase architecture
        #
        # @param options [Hash] Serialization options
        # @option options [Class] :mapper_class Model class for mapping lookup
        # @option options [String] :encoding Character encoding
        # @option options [Boolean] :declaration Include XML declaration
        # @option options [Boolean] :pretty Pretty-print output
        # @return [String] XML document
        def to_xml(options = {})
          # Accept xml_declaration from options if present (for model serialization)
          @xml_declaration = options[:xml_declaration] if options[:xml_declaration]

          # Accept input_namespaces from options if present (for namespace format preservation)
          @input_namespaces = options[:input_namespaces] if options[:input_namespaces]

          # Build XML using adapter-specific builder
          build_xml_document(options)
        end

        private

        # Build the XML document (template method)
        #
        # Override in adapter to use specific builder
        #
        # @param options [Hash] Serialization options
        # @return [String] XML document
        def build_xml_document(options)
          raise NotImplementedError,
                "Subclasses must implement #build_xml_document"
        end

        # Transform model instance to XmlElement tree
        #
        # @param model [Object] Model instance
        # @param mapper_class [Class] Model class
        # @param options [Hash] Serialization options
        # @return [XmlDataModel::XmlElement] Transformed element tree
        def transform_model_to_xml_element(model, mapper_class, options)
          transformation = mapper_class.transformation_for(:xml, register)
          transformation.transform(model, options)
        end

        # Check if model has custom map_all methods
        #
        # @param xml_mapping [Xml::Mapping] XML mapping
        # @return [Boolean] True if custom methods present
        def has_custom_map_all_methods?(xml_mapping)
          xml_mapping.raw_mapping&.custom_methods &&
            xml_mapping.raw_mapping.custom_methods[:to]
        end

        # Collect namespace needs from element
        #
        # @param element [XmlElement, Object] Element to collect from
        # @param mapping [Xml::Mapping] XML mapping
        # @param mapper_class [Class] Model class
        # @return [Hash] Namespace needs
        def collect_namespace_needs(element, mapping, mapper_class: nil)
          collector = NamespaceCollector.new(register)
          collector.collect(element, mapping, mapper_class: mapper_class)
        end

        # Plan namespace declarations
        #
        # @param element [XmlElement, Object] Element to plan for
        # @param mapping [Xml::Mapping] XML mapping
        # @param needs [Hash] Namespace needs
        # @param options [Hash] Serialization options
        # @return [DeclarationPlan] Declaration plan with tree structure
        def plan_namespace_declarations(element, mapping, needs, options: {})
          planner = DeclarationPlanner.new(register)
          planner.plan(element, mapping, needs, options: options)
        end

        # Determine encoding from options
        #
        # @param options [Hash] Options hash
        # @return [String, nil] Encoding string or nil
        def determine_encoding(options)
          options[:encoding] ||
            options[:parse_encoding] ||
            @encoding ||
            "UTF-8"
        end

        # Check if XML declaration should be included
        #
        # @param options [Hash] Options hash
        # @return [Boolean] True if declaration should be included
        def should_include_declaration?(options)
          options[:declaration] == true
        end

        # Generate final XML output with declaration and doctype
        #
        # @param xml_data [String] XML content
        # @param options [Hash] Serialization options
        # @return [String] Complete XML document
        def finalize_xml_output(xml_data, options)
          result = ""

          # Include declaration when encoding is specified OR when declaration is requested
          if (options[:encoding] && !options[:encoding].nil?) || should_include_declaration?(options)
            result += generate_declaration(options)
          end

          # Add DOCTYPE if present
          doctype_to_use = options[:doctype] || @doctype
          if doctype_to_use && !options[:omit_doctype]
            result += generate_doctype_declaration(doctype_to_use)
          end

          result += xml_data
          result
        end
      end
    end
  end
end
