# frozen_string_literal: true

module Lutaml
  module Xml
    # Base class for defining XML namespaces with full XSD generation support.
    #
    # This class provides a declarative DSL for defining namespace metadata
    # that follows W3C XML Namespace and XSD specifications.
    #
    # @example Basic namespace definition
    #   class ContactNamespace < Lutaml::Xml::Namespace
    #     uri 'https://example.com/schemas/contact/v1'
    #     schema_location 'https://example.com/schemas/contact/v1/contact.xsd'
    #     prefix_default 'contact'
    #   end
    #
    # @example Full namespace definition with XSD features
    #   class ContactNamespace < Lutaml::Xml::Namespace
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
    class Namespace
      # W3C-reserved namespace URIs and recommended alternatives
      W3C_RESERVED_URIS = {
        "http://www.w3.org/XML/1998/namespace" =>
          "Use Lutaml::Xml::W3c::XmlNamespace for xml: attributes (xml:lang, xml:space, etc.)",
        "http://www.w3.org/2001/XMLSchema-instance" =>
          "Use Lutaml::Xml::W3c::XsiNamespace for xsi: attributes (xsi:type, xsi:nil, etc.)",
        "http://www.w3.org/1999/xlink" =>
          "Use Lutaml::Xml::W3c::XlinkNamespace for xlink: attributes (xlink:href, xlink:type, etc.)",
        "http://www.w3.org/2001/XMLSchema" =>
          "Use Lutaml::Xml::W3c::XsNamespace for xs: schema elements (xs:element, xs:complexType, etc.)",
      }.freeze

      # W3C-reserved prefixes and recommended alternatives
      W3C_RESERVED_PREFIXES = {
        "xml" => "The 'xml' prefix is RESERVED per W3C. Use Lutaml::Xml::W3c::XmlNamespace for xml: attributes.",
        "xsi" => "Use Lutaml::Xml::W3c::XsiNamespace for xsi: attributes.",
        "xlink" => "Use Lutaml::Xml::W3c::XlinkNamespace for xlink: attributes.",
        "xs" => "Use Lutaml::Xml::W3c::XsNamespace for xs: schema elements.",
        "xsd" => "Use Lutaml::Xml::W3c::XsNamespace for xs: schema elements.",
      }.freeze

      class << self
        # Get or set the namespace URI
        #
        # @param value [String, nil] the namespace URI
        # @return [String, nil] the namespace URI
        def uri(value = nil)
          @uri_value = value if value
          @uri_value
        end

        # Get or set URI aliases for this namespace
        #
        # URI aliases allow a namespace to accept multiple URI variants during parsing.
        # The canonical URI (from `uri`) is used for model resolution, while alias URIs
        # are accepted on parse and serialized back as the original alias URI for round-trip fidelity.
        #
        # @param values [Array<String>] Array of alias URI strings
        # @return [Array<String>] All alias URIs
        #
        # @example ReqIF namespace with trailing slash variant
        #   class ReqIfNamespace < Lutaml::Xml::Namespace
        #     uri "http://www.omg.org/spec/ReqIF/20110401/reqif.xsd"
        #     uri_aliases "http://www.omg.org/spec/ReqIF/20110401/"
        #     prefix_default "reqif"
        #   end
        #
        # @example Multiple alias variants
        #   class XHTMLNamespace < Lutaml::Xml::Namespace
        #     uri "http://www.w3.org/1999/xhtml"
        #     uri_aliases "http://www.w3.org/1999/xhtml/", "http://www.w3.org/1999/xhtml"
        #     prefix_default "xhtml"
        #   end
        def uri_aliases(*values)
          @uri_aliases ||= []
          if values.any?
            values.each do |v|
              unless v.is_a?(String) && !v.empty?
                raise ArgumentError,
                      "uri_aliases requires non-empty String URIs"
              end
            end
            @uri_aliases.concat(values)
          end
          @uri_aliases
        end

        # Check if a URI is an alias of this namespace
        #
        # @param uri [String] The URI to check
        # @return [Boolean] true if the URI is an alias
        def is_alias?(uri)
          uri_aliases.include?(uri)
        end

        # Get all URIs for this namespace (canonical + aliases)
        #
        # @return [Array<String>] Array of all URI strings
        def all_uris
          [uri].compact + uri_aliases
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
            @element_form_default_set = true
          end
          @element_form_default_value || :unqualified
        end

        # Get or set attribute form default (:qualified or :unqualified)
        #
        # Controls whether locally declared attributes must be namespace-qualified
        # in instance documents.
        #
        # @param value [Symbol, nil] :qualified or :unqualified
        # @return [Symbol] the attribute form default (defaults to :unqualified per W3C)
        def attribute_form_default(value = nil)
          if value
            validate_form_value!(value, "attribute_form_default")
            @attribute_form_default_value = value
          end
          @attribute_form_default_value || :unqualified # W3C default is :unqualified
        end

        # Add imported namespaces (xs:import in XSD)
        #
        # Used when referencing types from other namespaces.
        #
        # @param namespaces [Array<Class>] Namespace classes to import
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

        # Skip W3C reserved namespace checks for built-in namespaces
        #
        # Built-in W3C namespaces (XmlNamespace, XsiNamespace, etc.) call this
        # to indicate they should not trigger warnings when instantiated.
        #
        # @param value [Boolean] true to skip W3C checks
        # @return [Boolean] the skip flag value
        def skip_w3c_reserved_check(value = nil)
          if value
            @skip_w3c_reserved_check = value
          end
          @skip_w3c_reserved_check
        end

        # Create an instance with optional runtime prefix override
        #
        # @param prefix [String, Symbol, nil] runtime prefix override
        # @return [Namespace] instance with resolved metadata
        def build(prefix: nil)
          new(prefix: prefix)
        end

        # Get the inheritance strategy for this namespace
        #
        # Returns the appropriate strategy based on element_form_default setting.
        # This determines whether child elements inherit the parent namespace.
        #
        # @return [Lutaml::Xml::NamespaceInheritanceStrategy]
        def inheritance_strategy
          case element_form_default
          when :qualified
            Lutaml::Xml::QualifiedInheritanceStrategy.new
          when :unqualified
            Lutaml::Xml::UnqualifiedInheritanceStrategy.new
          else
            raise ArgumentError,
                  "Invalid element_form_default: #{element_form_default.inspect}"
          end
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
          prefix = prefix_default
          namespace_uri = uri

          if prefix && !prefix.empty?
            "#{prefix}:#{namespace_uri}"
          else
            ":#{namespace_uri}"
          end
        end

        # Check if element_form_default was explicitly set (vs defaulted to :unqualified)
        #
        # @return [Boolean] true if element_form_default was explicitly set on this class
        def element_form_default_set?
          @element_form_default_set == true
        end

        private

        def validate_form_value!(value, method_name)
          valid_values = %i[qualified unqualified]
          return if valid_values.include?(value)

          raise ArgumentError,
                "#{method_name} must be :qualified or :unqualified, got #{value.inspect}"
        end

        def validate_namespace_class!(ns, method_name)
          return if ns.is_a?(Class) && ns < Namespace

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

        check_w3c_reserved!
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

      private

      # Check if this namespace class is built-in and should skip W3C reserved checks
      #
      # Built-in W3C namespaces (XmlNamespace, XsiNamespace, etc.) set
      # skip_w3c_reserved_check = true in their class body to opt out of warnings.
      #
      # @return [Boolean] true if this class has opted out of W3C checks
      def built_in_namespace?
        # Check the class object's own instance variable (not inherited)
        self.class.instance_variable_defined?(:@skip_w3c_reserved_check) &&
          self.class.instance_variable_get(:@skip_w3c_reserved_check)
      end

      # Check for W3C-reserved namespace definitions and warn users
      #
      # This warns users if they define a namespace that conflicts with
      # W3C-reserved URIs or prefixes, guiding them to use the
      # official Lutaml-provided W3C namespace classes instead.
      def check_w3c_reserved!
        return if built_in_namespace?

        uri_value = self.class.uri
        if uri_value && (message = W3C_RESERVED_URIS[uri_value])
          warn_w3c_reserved("W3C-reserved URI", uri_value, message)
          return
        end

        prefix_value = self.class.prefix_default
        if prefix_value && (message = W3C_RESERVED_PREFIXES[prefix_value])
          warn_w3c_reserved("W3C-reserved prefix '#{prefix_value}'",
                            prefix_value, message)
        end
      end

      # Issue a W3C reserved namespace warning
      #
      # @param type_desc [String] description of what is reserved
      # @param value [String] the reserved value
      # @param recommendation [String] what to use instead
      def warn_w3c_reserved(type_desc, value, recommendation)
        # Find the caller's location outside the gem
        gem_path = File.dirname(__dir__)
        location = caller_locations.find do |cl|
          !cl.path.start_with?(gem_path)
        end

        path = location ? "#{location.path}:#{location.lineno}:" : nil

        Lutaml::Model::Logger.warn(
          "Defining a namespace with #{type_desc} '#{value}'. " \
          "#{recommendation}",
          path,
        )
      end
    end
  end
end
