# frozen_string_literal: true

require "nokogiri"

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Validates XSD schema documents before parsing
        #
        # This validator checks that XML content is a valid XSD schema document
        # according to W3C XML Schema Definition Language (XSD) 1.0 or 1.1.
        # It performs pre-parsing validation to ensure the document structure
        # is correct before attempting to parse the schema.
        #
        # @example Validate an XSD 1.0 schema
        #   validator = Lutaml::Xml::Schema::Xsd::SchemaValidator.new(version: "1.0")
        #   validator.validate(xsd_content)
        #
        # @example Validate an XSD 1.1 schema
        #   validator = Lutaml::Xml::Schema::Xsd::SchemaValidator.new(version: "1.1")
        #   validator.validate(xsd_content)
        #
        class SchemaValidator
          # W3C XML Schema namespace
          XSD_NAMESPACE_1_0 = "http://www.w3.org/2001/XMLSchema"
          XSD_NAMESPACE_1_1 = "http://www.w3.org/2001/XMLSchema"
          XSD_NAMESPACE = XSD_NAMESPACE_1_0 # They use the same namespace

          # XSD 1.1 specific elements
          XSD_1_1_ELEMENTS = %w[
            assert
            assertion
            alternative
            openContent
            defaultOpenContent
          ].freeze

          # XSD 1.1 specific attributes
          XSD_1_1_ATTRIBUTES = %w[
            targetNamespace
            defaultAttributes
            xpathDefaultNamespace
          ].freeze

          # XSD 1.1 specific types
          XSD_1_1_TYPES = %w[
            anyAtomicType
            dateTimeStamp
            yearMonthDuration
            dayTimeDuration
          ].freeze

          attr_reader :version

          # Initialize a new SchemaValidator
          #
          # @param version [String] XSD version to validate against ("1.0" or "1.1")
          # @raise [ArgumentError] if version is not "1.0" or "1.1"
          def initialize(version: "1.0")
            unless %w[
              1.0 1.1
            ].include?(version)
              raise ArgumentError,
                    "Invalid XSD version: #{version}. Must be '1.0' or '1.1'"
            end

            @version = version
          end

          # Validate that content is a valid XSD schema
          #
          # @param content [String] XML content to validate
          # @return [true] if validation succeeds
          # @raise [SchemaValidationError] if validation fails with specific error message
          def validate(content)
            validate_xml_syntax(content)
            doc = parse_xml(content)
            validate_schema_root(doc)
            validate_schema_version(doc)
            true
          end

          # Detect the XSD version from schema content
          #
          # @param content [String] XML content to analyze
          # @return [String] Detected version ("1.0" or "1.1")
          def self.detect_version(content)
            doc = ::Nokogiri::XML(content)
            root = doc.root
            return "1.0" unless root

            # Check for XSD 1.1 specific features
            if has_xsd_1_1_features?(doc)
              "1.1"
            else
              # Check version attribute if present
              version_attr = root["version"]
              if version_attr&.start_with?("1.1")
                "1.1"
              else
                "1.0"
              end
            end
          rescue ::Nokogiri::XML::SyntaxError
            "1.0" # Default to 1.0 if cannot parse
          end

          # Check if document has XSD 1.1 specific features
          #
          # @param doc [Nokogiri::XML::Document] Parsed XML document
          # @return [Boolean] true if XSD 1.1 features are present
          def self.has_xsd_1_1_features?(doc)
            # Check for XSD 1.1 specific elements
            XSD_1_1_ELEMENTS.each do |element_name|
              nodes = doc.xpath("//xs:#{element_name}", "xs" => XSD_NAMESPACE)
              return true if nodes.any?

              nodes = doc.xpath("//xsd:#{element_name}", "xsd" => XSD_NAMESPACE)
              return true if nodes.any?
            end

            # Check for XSD 1.1 specific attributes
            root = doc.root
            return false unless root

            XSD_1_1_ATTRIBUTES.each do |attr_name|
              return true if root[attr_name] && attr_name == "defaultAttributes"
              return true if root[attr_name] && attr_name == "xpathDefaultNamespace"
            end

            # Check for XSD 1.1 specific types in type attributes
            type_attrs = doc.xpath("//*[@type]").map { |node| node["type"] }
            type_attrs.each do |type_ref|
              next unless type_ref

              # Extract local name from QName
              local_name = type_ref.include?(":") ? type_ref.split(":").last : type_ref
              return true if XSD_1_1_TYPES.include?(local_name)
            end

            false
          end

          private

          # Validate XML syntax
          #
          # @param content [String] XML content to validate
          # @raise [SchemaValidationError] if XML syntax is invalid
          def validate_xml_syntax(content)
            ::Nokogiri::XML(content, &:strict)
          rescue ::Nokogiri::XML::SyntaxError => e
            raise SchemaValidationError, "Invalid XML syntax: #{e.message}"
          end

          # Parse XML with error handling
          #
          # @param content [String] XML content to parse
          # @return [::Nokogiri::XML::Document] Parsed document
          # @raise [SchemaValidationError] if parsing fails
          def parse_xml(content)
            ::Nokogiri::XML(content)
          rescue ::Nokogiri::XML::SyntaxError => e
            raise SchemaValidationError, "Failed to parse XML: #{e.message}"
          end

          # Validate that root element is xs:schema
          #
          # @param doc [Nokogiri::XML::Document] Parsed XML document
          # @raise [SchemaValidationError] if root element is not a valid schema element
          def validate_schema_root(doc)
            root = doc.root

            raise SchemaValidationError, "Empty or invalid XML document" unless root

            # Check if root element is named "schema"
            unless root.name == "schema"
              raise SchemaValidationError,
                    "Not a valid XSD schema: root element must be 'schema', " \
                    "found '#{root.name}'"
            end

            # Check if root element has the correct namespace
            namespace_uri = root.namespace&.href
            return if namespace_uri == XSD_NAMESPACE

            if namespace_uri.nil?
              raise SchemaValidationError,
                    "Not a valid XSD schema: 'schema' element must be in the " \
                    "XML Schema namespace (#{XSD_NAMESPACE})"
            else
              raise SchemaValidationError,
                    "Not a valid XSD schema: 'schema' element has invalid namespace " \
                    "'#{namespace_uri}' (expected #{XSD_NAMESPACE})"
            end
          end

          # Validate schema version compatibility
          #
          # @param doc [Nokogiri::XML::Document] Parsed XML document
          # @raise [SchemaValidationError] if schema uses features incompatible with target version
          def validate_schema_version(doc)
            return if @version == "1.1" # 1.1 accepts all features

            # If validating as 1.0, check for 1.1 features
            return unless self.class.has_xsd_1_1_features?(doc)

            features = detect_1_1_features(doc)
            raise SchemaValidationError,
                  "Schema uses XSD 1.1 features but validator is set to version 1.0. " \
                  "Features found: #{features.join(', ')}. " \
                  "Use SchemaValidator.new(version: '1.1') to validate XSD 1.1 schemas."
          end

          # Detect which XSD 1.1 features are present
          #
          # @param doc [Nokogiri::XML::Document] Parsed XML document
          # @return [Array<String>] List of detected XSD 1.1 features
          def detect_1_1_features(doc)
            features = []

            # Check for specific elements
            XSD_1_1_ELEMENTS.each do |element_name|
              nodes = doc.xpath("//xs:#{element_name}", "xs" => XSD_NAMESPACE)
              nodes += doc.xpath("//xsd:#{element_name}", "xsd" => XSD_NAMESPACE)
              features << "xs:#{element_name}" if nodes.any?
            end

            # Check for specific attributes
            root = doc.root
            if root
              features << "defaultAttributes" if root["defaultAttributes"]
              features << "xpathDefaultNamespace" if root["xpathDefaultNamespace"]
            end

            # Check for specific types
            type_attrs = doc.xpath("//*[@type]").map { |node| node["type"] }
            type_attrs.each do |type_ref|
              next unless type_ref

              local_name = type_ref.include?(":") ? type_ref.split(":").last : type_ref
              features << "xs:#{local_name}" if XSD_1_1_TYPES.include?(local_name)
            end

            features.uniq
          end
        end
      end
    end
  end
end
