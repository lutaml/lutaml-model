require_relative "../config"

module Lutaml
  module Model
    module Type
      # Base class for all value types
      class Value
        attr_reader :value

        def initialize(value)
          @value = self.class.cast(value)
        end

        def initialized?
          true
        end

        def self.cast(value, _options = {})
          return nil if value.nil?

          value
        end

        def self.serialize(value)
          return nil if value.nil?

          new(value).to_s
        end

        # Instance methods for serialization
        def to_s
          value.to_s
        end

        # Class-level format conversion
        def self.from_format(value, format)
          new(send(:"from_#{format}", value))
        end

        # called from config when a new format is added
        def self.register_format_to_from_methods(format)
          define_method(:"to_#{format}") do
            value
          end

          define_singleton_method(:"from_#{format}") do |value|
            cast(value)
          end
        end

        # Class-level directive to set the XML namespace for this Value type
        #
        # @param ns_class [Class, nil] XmlNamespace class to associate with this type
        # @return [Class, nil] the XmlNamespace class
        #
        # @example Setting XML namespace for a Value type
        #   class EmailType < Lutaml::Model::Type::String
        #     xml_namespace EmailNamespace
        #     xsd_type 'EmailAddress'
        #   end
        def self.xml_namespace(ns_class = nil)
          if ns_class
            unless ns_class.is_a?(Class) && ns_class < Lutaml::Model::XmlNamespace
              raise ArgumentError,
                    "xml_namespace must be an XmlNamespace class, got #{ns_class.class}"
            end
            @namespace_class = ns_class
          end
          @namespace_class
        end

        # Backward compatibility alias for namespace directive
        #
        # @deprecated Use {xml_namespace} instead
        # @param ns_class [Class, nil] XmlNamespace class to associate with this type
        # @return [Class, nil] the XmlNamespace class
        def self.namespace(ns_class = nil)
          warn "[DEPRECATION] Type::Value.namespace is deprecated. " \
               "Use xml_namespace instead. " \
               "Called from #{caller(1..1).first}"
          xml_namespace(ns_class)
        end

        # Get the namespace URI for this Value type
        #
        # @return [String, nil] the namespace URI
        def self.namespace_uri
          @namespace_class&.uri
        end

        # Get the default namespace prefix for this Value type
        #
        # @return [String, nil] the namespace prefix
        def self.namespace_prefix
          @namespace_class&.prefix_default
        end

        # Class-level directive to set the XSD type name
        #
        # @param type_name [String, nil] XSD type name
        # @return [String] the XSD type name
        #
        # @example Setting XSD type
        #   class CustomType < Lutaml::Model::Type::Value
        #     xsd_type 'ct:CustomType'
        #   end
        def self.xsd_type(type_name = nil)
          @xsd_type = type_name if type_name
          @xsd_type || inherited_xsd_type || default_xsd_type
        end

        # Get inherited xsd_type from parent class
        #
        # @return [String, nil] parent's xsd_type if set
        def self.inherited_xsd_type
          return nil if superclass == Type::Value || !superclass.respond_to?(:xsd_type)

          # Get parent's @xsd_type directly (not default_xsd_type)
          parent_xsd = superclass.instance_variable_get(:@xsd_type)
          parent_xsd || superclass.inherited_xsd_type
        end

        # Default XSD type for this Value type
        #
        # Override in subclasses to provide specific default XSD types.
        #
        # @return [String] the default XSD type
        def self.default_xsd_type
          "xs:anyType"
        end

        # XML-specific configuration for Value types (DEPRECATED)
        #
        # @deprecated Use class-level `namespace` and `xsd_type` directives instead
        #
        # @yield block for XML configuration
        # @return [Lutaml::Model::Xml::ValueMapping] the XML mapping
        #
        # @example Old approach (deprecated)
        #   class NamePrefix < Lutaml::Model::Type::String
        #     xml do
        #       namespace NameAttributeNamespace
        #     end
        #   end
        #
        # @example New approach (recommended)
        #   class NamePrefix < Lutaml::Model::Type::String
        #     namespace NameAttributeNamespace
        #   end
        def self.xml(&block)
          if block
            warn "[DEPRECATION] Using xml block in Type::Value is deprecated. " \
                 "Use class-level 'namespace' directive instead."
          end
          @xml_mapping ||= ValueMapping.new
          @xml_mapping.instance_eval(&block) if block

          # Sync old block data to new directives for backward compatibility
          if @xml_mapping.namespace_class && !@namespace_class
            @namespace_class = @xml_mapping.namespace_class
          end

          @xml_mapping
        end

        # Get the XML mapping for this Value type
        #
        # @return [ValueMapping, nil] the XML mapping
        def self.xml_mapping
          @xml_mapping
        end

        # Simple mapping container for Value types
        #
        # Value types only need namespace information (no element/attribute mapping)
        class ValueMapping
          attr_reader :namespace_uri, :namespace_class

          def initialize
            @namespace_uri = nil
            @namespace_class = nil
          end

          # Set the namespace for this Value type
          #
          # @param uri_or_class [String, Class] namespace URI or XmlNamespace class
          # @return [void]
          #
          # @raise [ArgumentError] if invalid argument or prefix provided
          def namespace(uri_or_class)
            if uri_or_class.is_a?(Class) && uri_or_class < Lutaml::Model::XmlNamespace
              @namespace_class = uri_or_class
              @namespace_uri = uri_or_class.uri
            elsif uri_or_class.is_a?(String)
              @namespace_uri = uri_or_class
            else
              raise ArgumentError,
                    "namespace must be a String URI or XmlNamespace class, " \
                    "got #{uri_or_class.class}"
            end
          end
        end
      end
    end
  end
end
