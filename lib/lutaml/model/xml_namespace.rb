# frozen_string_literal: true

module Lutaml
  module Model
    # Base class for defining XML namespaces with full XSD generation support.
    #
    # This class provides a declarative DSL for defining namespace metadata
    # that follows W3C XML Namespace and XSD specifications.
    #
    # @example Basic namespace definition
    #   class ContactNamespace < Lutaml::Model::XmlNamespace
    #     uri 'https://example.com/schemas/contact/v1'
    #     schema_location 'https://example.com/schemas/contact/v1/contact.xsd'
    #     prefix_default 'contact'
    #   end
    #
    # @example Full namespace definition with XSD features
    #   class ContactNamespace < Lutaml::Model::XmlNamespace
    #     uri 'https://example.com/schemas/contact/v1'
    #     schema_location 'https://example.com/schemas/contact/v1/contact.xsd'
    #     prefix_default 'contact'
    #     element_form_default :qualified
    #     attribute_form_default :unqualified
    #     version '1.0'
    #
    #     imports AddressNamespace
    #     includes 'contact-common.xsd'
    #
    #     annotation do
    #       documentation "Contact information schema for Example Corp"
    #     end
    #   end
    class XmlNamespace
      class << self
        # Get or set the namespace URI
        #
        # @param value [String, nil] the namespace URI
        # @return [String, nil] the namespace URI
        def uri(value = nil)
          @uri_value = value if value
          @uri_value
        end

        # Get or set the schema location URL
        #
        # @param value [String, nil] the schema location URL
        # @return [String, nil] the schema location URL
        def schema_location(value = nil)
          @schema_location_value = value if value
          @schema_location_value
        end

        # Get or set the default prefix for this namespace
        #
        # @param value [String, Symbol, nil] the default prefix
        # @return [String, nil] the default prefix
        def prefix_default(value = nil)
          if value
            @prefix_default_value = value.to_s
          end
          @prefix_default_value
        end

        # Get or set element form default (:qualified or :unqualified)
        #
        # Controls whether locally declared elements must be namespace-qualified
        # in instance documents.
        #
        # @param value [Symbol, nil] :qualified or :unqualified
        # @return [Symbol] the element form default (defaults to :unqualified)
        def element_form_default(value = nil)
          if value
            validate_form_value!(value, "element_form_default")
            @element_form_default_value = value
          end
          @element_form_default_value || :unqualified
        end

        # Get or set attribute form default (:qualified or :unqualified)
        #
        # Controls whether locally declared attributes must be namespace-qualified
        # in instance documents.
        #
        # @param value [Symbol, nil] :qualified or :unqualified
        # @return [Symbol] the attribute form default (defaults to :unqualified)
        def attribute_form_default(value = nil)
          if value
            validate_form_value!(value, "attribute_form_default")
            @attribute_form_default_value = value
          end
          @attribute_form_default_value || :unqualified
        end

        # Add imported namespaces (xs:import in XSD)
        #
        # Used when referencing types from other namespaces.
        #
        # @param namespaces [Array<Class>] XmlNamespace classes to import
        # @return [Array<Class>] all imported namespaces
        def imports(*namespaces)
          @imports ||= []
          if namespaces.any?
            namespaces.each do |ns|
              validate_namespace_class!(ns, "imports")
            end
            @imports.concat(namespaces)
          end
          @imports
        end

        # Add included schema locations (xs:include in XSD)
        #
        # Used when including schema components from the same namespace.
        #
        # @param schemas [Array<String>] schema file locations to include
        # @return [Array<String>] all included schemas
        def includes(*schemas)
          @includes ||= []
          if schemas.any?
            schemas.each do |schema|
              unless schema.is_a?(String)
                raise ArgumentError,
                      "includes requires String schema locations, got #{schema.class}"
              end
            end
            @includes.concat(schemas)
          end
          @includes
        end

        # Get or set the schema version
        #
        # @param value [String, nil] the schema version
        # @return [String, nil] the schema version
        def version(value = nil)
          @version_value = value if value
          @version_value
        end

        # Define annotation block for the schema
        #
        # @yield block for defining annotations
        # @return [Proc, nil] the annotation block
        def annotation(&block)
          @annotation_value = block if block
          @annotation_value
        end

        # Get or set documentation text
        #
        # @param text [String, nil] the documentation text
        # @return [String, nil] the documentation text
        def documentation(text = nil)
          @documentation_value = text if text
          @documentation_value
        end

        # Create an instance with optional runtime prefix override
        #
        # @param prefix [String, Symbol, nil] runtime prefix override
        # @return [XmlNamespace] instance with resolved metadata
        def build(prefix: nil)
          new(prefix: prefix)
        end

        # Generate unique key for this namespace configuration
        #
        # The key is based on prefix and URI, ensuring that same config = same key.
        # This enables proper deduplication and lookup in hash structures.
        #
        # Format:
        # - With prefix: "prefix:uri"
        # - Without prefix (default namespace): ":uri"
        #
        # @return [String] unique key for hash lookups
        #
        # @example
        #   FooNamespace.to_key  # => "foo:http://example.com/foo"
        #   BarNamespace.to_key  # => ":http://example.com/bar"
        #
        # @api private
        def to_key
          "#{prefix_default}:#{uri}"
        end

        private

        def validate_form_value!(value, method_name)
          valid_values = %i[qualified unqualified]
          return if valid_values.include?(value)

          raise ArgumentError,
                "#{method_name} must be :qualified or :unqualified, got #{value.inspect}"
        end

        def validate_namespace_class!(ns, method_name)
          return if ns.is_a?(Class) && ns < XmlNamespace

          raise ArgumentError,
                "#{method_name} requires XmlNamespace classes, got #{ns.class}"
        end
      end

      # Instance attributes for runtime resolution
      attr_reader :uri, :schema_location, :prefix, :element_form_default,
                  :attribute_form_default, :version, :imports, :includes,
                  :documentation

      # Initialize instance with resolved metadata
      #
      # @param prefix [String, Symbol, nil] optional prefix override
      def initialize(prefix: nil)
        @uri = self.class.uri
        @schema_location = self.class.schema_location
        @prefix = prefix&.to_s || self.class.prefix_default
        @element_form_default = self.class.element_form_default
        @attribute_form_default = self.class.attribute_form_default
        @version = self.class.version
        @imports = self.class.imports
        @includes = self.class.includes
        @documentation = self.class.documentation
      end

      # Get the XML attribute name for namespace declaration
      #
      # @return [String] "xmlns" or "xmlns:prefix"
      def attr_name
        if prefix && !prefix.empty?
          "xmlns:#{prefix}"
        else
          "xmlns"
        end
      end

      # Check if this namespace has a prefix
      #
      # @return [Boolean] true if prefix is defined
      def prefixed?
        !!(prefix && !prefix.empty?)
      end

      # Check if this namespace is qualified for elements
      #
      # @return [Boolean] true if element_form_default is :qualified
      def elements_qualified?
        element_form_default == :qualified
      end

      # Check if this namespace is qualified for attributes
      #
      # @return [Boolean] true if attribute_form_default is :qualified
      def attributes_qualified?
        attribute_form_default == :qualified
      end
    end
  end
end
