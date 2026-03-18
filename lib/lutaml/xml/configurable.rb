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
        # @yield block for XML configuration
        # @return [Object] the XML mapping object
        #
        # @example Configuration for Model class
        #   xml do
        #     root 'MyModel'
        #     namespace MyNamespace
        #     map_element 'name', to: :name
        #   end
        #
        # @example Configuration for Type class
        #   xml do
        #     namespace MyNamespace
        #     xsd_type 'my:CustomType'
        #   end
        def xml(&block)
          @xml_mapping ||= create_xml_mapping
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
      end
    end
  end
end
