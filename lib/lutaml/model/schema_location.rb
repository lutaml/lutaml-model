# frozen_string_literal: true

module Lutaml
  module Model
    # Location represents a single namespace-to-schema-location mapping
    # Used within xsi:schemaLocation attribute values
    #
    # @example
    #   class MyNs < Lutaml::Model::Xml::W3c::XmlNamespace
    #     uri "http://example.com/ns"
    #   end
    #
    #   loc = Location.new(
    #     namespace_class: MyNs,
    #     location: "http://example.com/schema.xsd"
    #   )
    class Location
      attr_reader :namespace_class, :location

      # @param namespace_class [Class] An XmlNamespace subclass defining the namespace
      # @param location [String] The URL or path to the schema definition
      def initialize(namespace_class:, location:)
        unless namespace_class.is_a?(Class) && namespace_class < XmlNamespace
          raise ArgumentError,
                "namespace_class must be an XmlNamespace subclass, got #{namespace_class.class}. " \
                "String namespace URIs are no longer supported."
        end

        @namespace_class = namespace_class
        @location = location
      end

      # Returns the namespace URI from the XmlNamespace class
      # @return [String]
      def namespace
        namespace_class.uri
      end

      # Format for xsi:schemaLocation attribute value (space-separated pair)
      # @return [String] "namespace_uri schema_location"
      def to_xml_attribute
        "#{namespace} #{location}".strip
      end

      def eql?(other)
        other.class == self.class &&
          namespace_class == other.namespace_class &&
          location == other.location
      end
      alias == eql?

      def hash
        [namespace_class, location].hash
      end
    end

    # SchemaLocation manages xsi:schemaLocation attribute which provides
    # schema validation hints as namespace-location pairs
    #
    # Uses W3C XmlSchema-instance namespace (xsi) for the schemaLocation attribute itself.
    # Each location pair associates a namespace (via XmlNamespace class) with its schema URL.
    #
    # @example Creating a schema location
    #   class MyNs < Lutaml::Model::Xml::W3c::XmlNamespace
    #     uri "http://example.com/ns"
    #   end
    #
    #   schema_loc = SchemaLocation.new(
    #     locations: {
    #       MyNs => "http://example.com/schema.xsd"
    #     }
    #   )
    #
    # @example With custom xsi prefix
    #   schema_loc = SchemaLocation.new(
    #     locations: { MyNs => "http://example.com/schema.xsd" },
    #     xsi_prefix: "xmlschema-instance"
    #   )
    class SchemaLocation
      attr_reader :schema_location, :xsi_prefix

      # @param locations [Hash{Class => String}, Array<Location>] namespace class to location mapping or Location array
      # @param xsi_prefix [String] prefix for XMLSchema-instance namespace (default: "xsi")
      def initialize(locations:, xsi_prefix: "xsi")
        @schema_location = build_locations(locations)
        @xsi_prefix = xsi_prefix
      end

      # Returns the XMLSchema-instance namespace class
      # @return [Class] Xml::W3c::XsiNamespace
      def xsi_namespace_class
        Xml::W3c::XsiNamespace
      end

      # Returns the XMLSchema-instance namespace URI
      # @return [String]
      def xsi_namespace
        xsi_namespace_class.uri
      end

      # Generate XML attributes for schema location declaration
      # @return [Hash{String => String}] xmlns and schemaLocation attributes
      def to_xml_attributes
        {
          "xmlns:#{xsi_prefix}" => xsi_namespace,
          "#{xsi_prefix}:schemaLocation" => schema_location.map(&:to_xml_attribute).join(" "),
        }
      end

      def [](index)
        @schema_location[index]
      end

      def size
        @schema_location.size
      end

      private

      # Build Location objects from various input formats
      # @param locations [Hash, Array, String] input locations
      # @return [Array<Location>] array of Location objects
      def build_locations(locations)
        if locations.is_a?(::Hash)
          # Hash{XmlNamespace class => location string}
          locations.map do |ns_class, loc|
            Location.new(namespace_class: ns_class, location: loc)
          end
        elsif locations.is_a?(::Array)
          # Array of Location objects or [ns_class, location] pairs
          locations.map do |item|
            if item.is_a?(Location)
              item
            elsif item.is_a?(::Array) && item.size == 2
              Location.new(namespace_class: item[0], location: item[1])
            else
              raise ArgumentError, "Invalid location array item: #{item.inspect}"
            end
          end
        elsif locations.is_a?(::String)
          # Legacy string format "uri location uri location..."
          # This should crash to prevent string usage
          raise ArgumentError,
                "String schema locations are no longer supported. " \
                "Use Hash{XmlNamespace class => location} or Array<Location> instead. " \
                "Got: #{locations.inspect}"
        else
          raise ArgumentError, "Invalid locations type: #{locations.class}"
        end
      end
    end
  end
end
