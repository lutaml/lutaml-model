# frozen_string_literal: true

module Lutaml
  module Xml
    module Type
      # XML configuration concern for Type::Value classes
      #
      # Include this module in Type::Value to provide XML configuration
      # methods that support inheritance from parent types.
      #
      # @example Including in a Value type
      #   class MyType < Lutaml::Model::Type::String
      #     include Lutaml::Xml::Type::Configurable
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
          # XML configuration block for Value types
          #
          # Provides unified XML configuration API for Type classes.
          # Supports inheritance from parent types.
          #
          # @yield block for XML configuration
          # @return [Lutaml::Xml::Type::ValueXmlMapping] the XML mapping
          #
          # @example Using xml block for configuration
          #   class EmailType < Lutaml::Model::Type::String
          #     xml do
          #       namespace EmailNamespace
          #       xsd_type 'EmailAddress'
          #     end
          #   end
          def xml(&block)
            if block
              @xml_mapping ||= inherit_xml_mapping_from_parent # rubocop:disable Naming/MemoizedInstanceVariableName
              @xml_mapping.instance_eval(&block)
            end
            @xml_mapping ||= inherit_xml_mapping_from_parent # rubocop:disable Naming/MemoizedInstanceVariableName
          end

          # Get the XML mapping for this Value type
          #
          # @return [Lutaml::Xml::Type::ValueXmlMapping, nil] the XML mapping
          def xml_mapping
            @xml_mapping
          end

          # Get the namespace URI for this Value type
          #
          # @return [String, nil] the namespace URI
          def namespace_uri
            ns = namespace_class
            return nil unless ns
            return nil if %i[blank inherit].include?(ns)

            ns.uri
          end

          # Get the default namespace prefix for this Value type
          #
          # @return [String, nil] the namespace prefix
          def namespace_prefix
            ns = namespace_class
            return nil unless ns
            return nil if %i[blank inherit].include?(ns)

            ns.prefix_default
          end

          # Get the namespace class for this Value type
          #
          # @return [Class, Symbol, nil] the namespace class or symbol
          def namespace_class
            xml_mapping&.namespace_class || inherited_namespace
          end

          # Class-level directive to set the XSD type name
          #
          # @param type_name [String, Symbol, Class, nil] XSD type name, Type class, or nil
          # @return [String] the XSD type name
          #
          # @example Setting XSD type
          #   class CustomType < Lutaml::Model::Type::Value
          #     xsd_type 'ct:CustomType'
          #   end
          def xsd_type(type_name = nil)
            @xsd_type = type_name if type_name
            @xsd_type || inherited_xsd_type || default_xsd_type
          end

          # Get inherited xsd_type from parent class
          #
          # @return [String, nil] parent's xsd_type if set
          def inherited_xsd_type
            return nil if superclass == Lutaml::Model::Type::Value
            return nil unless superclass.respond_to?(:xsd_type)

            # Get parent's @xsd_type directly (not default_xsd_type)
            parent_xsd = superclass.instance_variable_get(:@xsd_type)
            parent_xsd || superclass.inherited_xsd_type
          end

          # Get inherited namespace from parent class
          #
          # @return [Class, Symbol, nil] parent's namespace class if set
          def inherited_namespace
            return nil if superclass == Lutaml::Model::Type::Value
            return nil unless superclass.respond_to?(:xml_mapping)

            parent_mapping = superclass.xml_mapping
            parent_mapping&.namespace_class || superclass.inherited_namespace
          end

          # Default XSD type for this Value type
          #
          # Override in subclasses to provide specific default XSD types.
          #
          # @return [String] the default XSD type
          def default_xsd_type
            "xs:anyType"
          end

          # Create a new XML mapping, inheriting from parent if available
          #
          # @return [Lutaml::Xml::Type::ValueXmlMapping] the new XML mapping
          def inherit_xml_mapping_from_parent
            return create_xml_mapping if superclass == Lutaml::Model::Type::Value
            return create_xml_mapping unless superclass.respond_to?(:xml_mapping)

            parent_mapping = superclass.xml_mapping
            return create_xml_mapping unless parent_mapping

            parent_mapping.deep_dup
          end

          # Create a new XML mapping instance
          #
          # @return [Lutaml::Xml::Type::ValueXmlMapping] a new mapping instance
          def create_xml_mapping
            Lutaml::Xml::Type::ValueXmlMapping.new
          end
        end
      end
    end
  end
end
