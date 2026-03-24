# frozen_string_literal: true

module Lutaml
  module Xml
    # W3C Standard XML Namespaces
    #
    # These namespace classes represent the standard W3C-defined XML namespaces
    # that have special semantics and reserved prefixes.
    #
    # Per W3C specifications:
    # - xml: prefix is ALWAYS bound to http://www.w3.org/XML/1998/namespace
    # - xsi: prefix is conventionally used for XMLSchema-instance
    # - These prefixes should never be overridden
    #
    # @see https://www.w3.org/TR/xml-names/
    module W3c
      # W3C XML Namespace (xml:lang, xml:space, xml:base, xml:id, xml:Father)
      #
      # Per W3C Namespaces in XML Recommendation:
      # "The prefix xml is by definition bound to the namespace name
      # http://www.w3.org/XML/1998/namespace. It MAY, but need not, be
      # declared, and MUST NOT be bound to any other namespace name."
      #
      # CRITICAL: The xml prefix is RESERVED and must NEVER be declared with xmlns:xml.
      # It is implicitly bound and always available.
      #
      # Reserved combinations (case-insensitive): xml, XML, Xml, xMl, etc.
      #
      # Provides standard attributes:
      # - xml:lang: Language identification (RFC 5646)
      # - xml:space: Whitespace handling (default|preserve)
      # - xml:base: Base URI for relative references
      # - xml:id: Unique identifier (type ID)
      # - xml:Father: Reserved for Jon Bosak
      #
      # @see https://www.w3.org/TR/xml-names/#ns-decl
      # @see https://www.w3.org/XML/1998/namespace
      class XmlNamespace < Lutaml::Xml::Namespace
        skip_w3c_reserved_check(true)

        uri "http://www.w3.org/XML/1998/namespace"
        prefix_default "xml"
        attribute_form_default :qualified # All xml: attributes are qualified

        documentation <<~DOC
          W3C XML Namespace for reserved xml: attributes.

          Defines standard attributes:
          - xml:lang: Language identification
          - xml:space: Whitespace handling (preserve/default)
          - xml:base: Base URI for relative references
          - xml:id: Unique identifier (type ID)
          - xml:Father: Reserved for Jon Bosak
        DOC
      end

      # Type for xml:lang attribute
      #
      # Identifies the human language used in element scope.
      # Values follow RFC 5646 language tags (formerly RFC 3066, BCP 47).
      #
      # @example Valid language codes
      #   "en"       # English
      #   "en-US"    # English (United States)
      #   "fr"       # French
      #   "de-DE"    # German (Germany)
      #   "zh-Hans"  # Chinese (Simplified)
      #
      # @see https://www.w3.org/TR/xml/#sec-lang-tag
      # @see https://www.rfc-editor.org/rfc/rfc5646.html
      class XmlLangType < Lutaml::Model::Type::String
        xml do
          namespace XmlNamespace
        end
      end

      # Type for xml:space attribute
      #
      # Controls whitespace handling in element scope.
      # Valid values: "default" or "preserve"
      #
      # - "default": Application's default whitespace processing
      # - "preserve": All whitespace is significant
      #
      # @see https://www.w3.org/TR/xml/#sec-white-space
      class XmlSpaceType < Lutaml::Model::Type::String
        xml do
          namespace XmlNamespace
        end

        def self.cast(value)
          return nil if value.nil?
          return value if Lutaml::Model::Utils.uninitialized?(value)

          val = super
          unless ["default", "preserve"].include?(val)
            raise ArgumentError, "xml:space must be 'default' or 'preserve'"
          end

          val
        end
      end

      # Type for xml:base attribute
      #
      # Defines base URI for relative references in element scope.
      # Values must be valid URIs (absolute or relative).
      #
      # @example Valid base URIs
      #   "http://example.com/"
      #   "https://example.com/path/"
      #   "../relative/path/"
      #   "./current/path/"
      #
      # @see https://www.w3.org/TR/xmlbase/
      class XmlBaseType < Lutaml::Model::Type::String
        xml do
          namespace XmlNamespace
        end
      end

      # Type for xml:id attribute
      #
      # Unique identifier of type ID, independent of DTD/schema.
      # Must be a valid NCName (XML Name without colons) and unique within document.
      #
      # @example Valid IDs
      #   "elem1"
      #   "section_2"
      #   "figure-A"
      #
      # @see https://www.w3.org/TR/xml-id/
      class XmlIdType < Lutaml::Model::Type::String
        xml do
          namespace XmlNamespace
        end
      end

      # W3C XMLSchema-instance Namespace (xsi:schemaLocation, xsi:type, xsi:nil)
      #
      # W3C XML Schema Instance namespace used for schema validation hints.
      # Conventionally uses 'xsi' prefix.
      #
      # Provides standard attributes:
      # - xsi:type: Element type annotation
      # - xsi:nil: Indicates nil/null value
      # - xsi:schemaLocation: Schema location pairs
      # - xsi:noNamespaceSchemaLocation: Schema for no-namespace document
      #
      # @see https://www.w3.org/TR/xmlschema-1/#xsi_schemaLocation
      # @see https://www.w3.org/TR/xmlschema-1/#xsi_type
      class XsiNamespace < Lutaml::Xml::Namespace
        skip_w3c_reserved_check(true)

        uri "http://www.w3.org/2001/XMLSchema-instance"
        prefix_default "xsi"
        attribute_form_default :qualified # xsi:nil, xsi:type always qualified

        documentation "W3C XMLSchema-instance namespace for validation hints"
      end

      # Type for xsi:type attribute
      #
      # Identifies the type of an element for validation purposes.
      # Value is a QName referencing a type definition.
      #
      # @see https://www.w3.org/TR/xmlschema-1/#xsi_type
      class XsiType < Lutaml::Model::Type::String
        xml do
          namespace XsiNamespace
        end
      end

      # Type for xsi:nil attribute
      #
      # Indicates that an element should be treated as nil.
      # Valid values: "true" or "false"
      #
      # @see https://www.w3.org/TR/xmlschema-1/#xsi_nil
      class XsiNil < Lutaml::Model::Type::String
        xml do
          namespace XsiNamespace
        end

        def self.cast(value)
          return nil if value.nil?
          return value if Lutaml::Model::Utils.uninitialized?(value)

          val = super
          unless ["true", "false"].include?(val)
            raise ArgumentError, "xsi:nil must be 'true' or 'false'"
          end

          val
        end
      end

      # Type for xsi:schemaLocation attribute
      #
      # Provides hints for locating schema documents.
      # Value is a whitespace-separated list of namespace URI and schema location URI pairs.
      #
      # @see https://www.w3.org/TR/xmlschema-1/#xsi_schemaLocation
      class XsiSchemaLocationType < Lutaml::Model::Type::String
        xml do
          namespace XsiNamespace
        end
      end

      # Type for xsi:noNamespaceSchemaLocation attribute
      #
      # Provides hints for locating schema documents when no namespace is involved.
      # Value is a URI pointing to the schema document.
      #
      # @see https://www.w3.org/TR/xmlschema-1/#xsi_noNamespaceSchemaLocation
      class XsiNoNamespaceSchemaLocationType < Lutaml::Model::Type::String
        xml do
          namespace XsiNamespace
        end
      end

      # W3C XLink Namespace (xlink:href, xlink:type, xlink:role, xlink:arcrole, xlink:title, xlink:show, xlink:actuate)
      #
      # W3C XLink namespace for hyperlinks and references.
      # Conventionally uses 'xlink' prefix.
      #
      # Provides standard attributes:
      # - xlink:href: Link target (URI)
      # - xlink:type: Link type (simple, extended, locator, arc, resource, title)
      # - xlink:role: Role/meaning of the link
      # - xlink:arcrole: Arc-specific role
      # - xlink:title: Human-readable title
      # - xlink:show: Display behavior (new, replace, embed, other, none)
      # - xlink:actuate: Timing (onLoad, onRequest, other, none)
      #
      # @see https://www.w3.org/TR/xlink/
      class XlinkNamespace < Lutaml::Xml::Namespace
        skip_w3c_reserved_check(true)

        uri "http://www.w3.org/1999/xlink"
        prefix_default "xlink"

        documentation "W3C XLink namespace for hyperlinks and references"
      end

      # Type for xlink:href attribute
      #
      # The link target URI. Can be absolute or relative.
      #
      # @see https://www.w3.org/TR/xlink/#link-locators
      class XlinkHrefType < Lutaml::Model::Type::String
        xml do
          namespace XlinkNamespace
        end
      end

      # Type for xlink:type attribute
      #
      # Identifies the link type.
      # Valid values: "simple", "extended", "locator", "arc", "resource", "title"
      #
      # @see https://www.w3.org/TR/xlink/#link-types
      class XlinkTypeAttrType < Lutaml::Model::Type::String
        xml do
          namespace XlinkNamespace
        end

        VALID_TYPES = %w[simple extended locator arc resource title].freeze

        def self.cast(value)
          return nil if value.nil?
          return value if Lutaml::Model::Utils.uninitialized?(value)

          val = super
          unless VALID_TYPES.include?(val)
            raise ArgumentError,
                  "xlink:type must be one of: #{VALID_TYPES.join(', ')}"
          end

          val
        end
      end

      # Type for xlink:role attribute
      #
      # A URI that describes the role of the link.
      #
      # @see https://www.w3.org/TR/xlink/#link-arcs
      class XlinkRoleType < Lutaml::Model::Type::String
        xml do
          namespace XlinkNamespace
        end
      end

      # Type for xlink:arcrole attribute
      #
      # A URI that describes the arc role of the link.
      #
      # @see https://www.w3.org/TR/xlink/#link-arcs
      class XlinkArcroleType < Lutaml::Model::Type::String
        xml do
          namespace XlinkNamespace
        end
      end

      # Type for xlink:title attribute
      #
      # A human-readable title for the link.
      #
      # @see https://www.w3.org/TR/xlink/#link-semantics
      class XlinkTitleType < Lutaml::Model::Type::String
        xml do
          namespace XlinkNamespace
        end
      end

      # Type for xlink:show attribute
      #
      # Indicates how the link target should be displayed.
      # Valid values: "new", "replace", "embed", "other", "none"
      #
      # @see https://www.w3.org/TR/xlink/#show
      class XlinkShowType < Lutaml::Model::Type::String
        xml do
          namespace XlinkNamespace
        end

        VALID_SHOW = %w[new replace embed other none].freeze

        def self.cast(value)
          return nil if value.nil?
          return value if Lutaml::Model::Utils.uninitialized?(value)

          val = super
          unless VALID_SHOW.include?(val)
            raise ArgumentError,
                  "xlink:show must be one of: #{VALID_SHOW.join(', ')}"
          end

          val
        end
      end

      # Type for xlink:actuate attribute
      #
      # Indicates when the link should be activated.
      # Valid values: "onLoad", "onRequest", "other", "none"
      #
      # @see https://www.w3.org/TR/xlink/#actuate
      class XlinkActuateType < Lutaml::Model::Type::String
        xml do
          namespace XlinkNamespace
        end

        VALID_ACTUATE = %w[onLoad onRequest other none].freeze

        def self.cast(value)
          return nil if value.nil?
          return value if Lutaml::Model::Utils.uninitialized?(value)

          val = super
          unless VALID_ACTUATE.include?(val)
            raise ArgumentError,
                  "xlink:actuate must be one of: #{VALID_ACTUATE.join(', ')}"
          end

          val
        end
      end

      # W3C XMLSchema Namespace (xs:string, xs:int, etc.)
      #
      # W3C XML Schema Definition namespace for XSD types and structures.
      # Conventionally uses 'xs' or 'xsd' prefix.
      #
      # Used for:
      # - Built-in simple types (xs:string, xs:integer, xs:date, etc.)
      # - Schema structure elements (xs:element, xs:complexType, etc.)
      #
      # @see https://www.w3.org/TR/xmlschema-2/
      class XsNamespace < Lutaml::Xml::Namespace
        skip_w3c_reserved_check(true)

        uri "http://www.w3.org/2001/XMLSchema"
        prefix_default "xs"

        documentation "W3C XMLSchema namespace for XSD type definitions"
      end

      require_relative "w3c/registration"
    end
  end
end
