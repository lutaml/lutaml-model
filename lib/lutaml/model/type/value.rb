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

        # XML-specific configuration for Value types
        #
        # This allows Value types to declare namespace information
        # for XSD generation purposes.
        #
        # @yield block for XML configuration
        # @return [Lutaml::Model::Xml::ValueMapping] the XML mapping
        #
        # @example Declaring namespace for a Value type
        #   class NamePrefix < Lutaml::Model::Type::String
        #     xml do
        #       namespace NameAttributeNamespace
        #     end
        #   end
        def self.xml(&block)
          @xml_mapping ||= ValueMapping.new
          @xml_mapping.instance_eval(&block) if block
          @xml_mapping
        end

        # Get the XML mapping for this Value type
        #
        # @return [ValueMapping, nil] the XML mapping
        def self.xml_mapping
          @xml_mapping
        end

        # Get the XSD type for this Value type
        #
        # Override in subclasses to provide specific XSD types.
        #
        # @return [String] the XSD type (default: xs:anyType)
        def self.xsd_type
          "xs:anyType"
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
