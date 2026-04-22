# frozen_string_literal: true

module Lutaml
  module Xml
    # Unified XML configuration interface for Model and Type classes
    #
    # This module provides a common interface for XML configuration
    # that can be included in both Model classes (via Serializable) and
    # Type classes (via Type::Value).
    #
    # @example Including in a class
    #   class MyModel < Lutaml::Model::Serializable
    #     include Lutaml::Xml::Configurable
    #
    #     xml do
    #       root 'MyModel'
    #       namespace MyNamespace
    #     end
    #   end
    #
    # @example In a Type class
    #   class MyType < Lutaml::Model::Type::String
    #     include Lutaml::Xml::Configurable
    #
    #     xml do
    #       namespace MyNamespace
    #       xsd_type 'my:CustomType'
    #     end
    #   end
    #
    module Configurable
      # Hook to extend including class with ClassMethods
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Class methods for XML configuration
      module ClassMethods
        # XML configuration block
        #
        # Provides unified XML configuration API. The behavior differs
        # between Model and Type classes:
        # - Model classes use Lutaml::Xml::Mapping
        # - Type classes use Lutaml::Model::Type::ValueXmlMapping
        #
        # @overload xml(&block)
        #   Configure XML mapping inline with a block.
        #
        #   @yield block for XML configuration
        #   @return [Object] the XML mapping object
        #
        #   @example Configuration with block
        #     xml do
        #       root 'MyModel'
        #       namespace MyNamespace
        #       map_element 'name', to: :name
        #     end
        #
        # @overload xml(mapping_class, &block)
        #   Inherit from a reusable mapping class and optionally add more config.
        #
        #   @param mapping_class [Class] A Lutaml::Xml::Mapping subclass
        #   @yield optional block for additional configuration
        #   @return [Object] the XML mapping object
        #
        #   @example Reference a mapping class
        #     xml MyMapping
        #
        #   @example Reference a mapping class with additional config
        #     xml MyMapping do
        #       map_element 'Extra', to: :extra
        #     end
        def xml(mapping_class = nil, &block)
          @xml_mapping ||= create_xml_mapping

          if mapping_class
            if mapping_class < Lutaml::Xml::Mapping
              inherit_mapping_from(mapping_class)
            elsif mapping_class.is_a?(Class)
              raise ArgumentError,
                    "#{mapping_class} must be a subclass of Lutaml::Xml::Mapping"
            end
          end

          @xml_mapping.instance_eval(&block) if block
          @xml_mapping
        end

        # Get the XML mapping for this class
        #
        # @return [Object, nil] the XML mapping object
        def xml_mapping
          @xml_mapping
        end

        # Create a new XML mapping instance
        #
        # Override in including class to provide specific mapping type.
        # Model classes should return Lutaml::Xml::Mapping.new
        # Type classes should return Lutaml::Model::Type::ValueXmlMapping.new
        #
        # @return [Object] a new mapping instance
        # @raise [NotImplementedError] if not overridden
        def create_xml_mapping
          raise NotImplementedError,
                "#{self.class} must implement #create_xml_mapping"
        end

        public :xml, :xml_mapping, :create_xml_mapping

        private

        # Inherit all mappings from a mapping class into this class's XML mapping.
        #
        # Copies all element mappings, attribute mappings, namespace scope,
        # and other configuration from the parent mapping class.
        #
        # @param mapping_class [Class] A Lutaml::Xml::Mapping subclass
        # @return [void]
        def inherit_mapping_from(mapping_class)
          # Get the parent mapping instance that has DSL already evaluated
          parent_mapping = if mapping_class.respond_to?(:xml_mapping_instance) &&
              mapping_class.xml_mapping_instance
                             mapping_class.xml_mapping_instance
                           else
                             mapping_class.new
                           end

          # Inherit declared namespaces (merge, avoid duplicates)
          existing_ns = @xml_mapping.namespace_scope || []
          parent_ns = parent_mapping.namespace_scope || []
          all_ns = (existing_ns + parent_ns).uniq
          @xml_mapping.namespace_scope(all_ns) if all_ns.any?

          # Merge element mappings
          parent_mapping.mapping_elements_hash.each do |key, rule|
            existing = @xml_mapping.elements_hash[key]
            if existing.nil?
              @xml_mapping.elements_hash[key] =
                rule.deep_dup
            elsif existing.is_a?(Array) && rule.is_a?(Array)
              # Both have multiple rules for this key - merge and dedupe
              merged = (existing + rule).reject do |r|
                existing.any? do |e|
                  e.eql?(r)
                end
              end
              @xml_mapping.elements_hash[key] = merged
            elsif existing.is_a?(Array)
              # Existing has multiple, parent has single
              unless existing.any? { |e| e.eql?(rule) }
                existing << rule.deep_dup
              end
            elsif rule.is_a?(Array)
              # Parent has multiple, existing has single
              unless rule.any? { |r| r.eql?(existing) }
                @xml_mapping.elements_hash[key] =
                  [existing, *rule]
              end
            elsif !existing.eql?(rule)
              # Different single rules - convert to array (polymorphic)
              @xml_mapping.elements_hash[key] =
                [existing, rule.deep_dup]
            end
          end

          # Merge attribute mappings
          parent_mapping.mapping_attributes_hash.each do |key, rule|
            existing = @xml_mapping.attributes_hash[key]
            if existing.nil?
              @xml_mapping.attributes_hash[key] =
                rule.deep_dup
            elsif existing.is_a?(Array) && rule.is_a?(Array)
              merged = (existing + rule).reject do |r|
                existing.any? do |e|
                  e.eql?(r)
                end
              end
              @xml_mapping.attributes_hash[key] = merged
            elsif existing.is_a?(Array)
              unless existing.any? { |e| e.eql?(rule) }
                existing << rule.deep_dup
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

          # Inherit element/root configuration
          if parent_mapping.element_name && !@xml_mapping.element_name
            @xml_mapping.element(parent_mapping.element_name)
          end

          if parent_mapping.namespace_class && !@xml_mapping.namespace_class?
            @xml_mapping.namespace(parent_mapping.namespace_class)
          end

          if parent_mapping.namespace_param == :inherit && !@xml_mapping.namespace_set?
            @xml_mapping.namespace(:inherit)
          end

          # Inherit parent mapping reference for listener collection
          @xml_mapping.inherit_from(mapping_class)
        end
      end
    end
  end
end
