module Lutaml
  module Model
    class SchemaLocation
      attr_reader :namespace, :prefix, :schema_location

      def initialize(schema_location, prefix = "xsi", namespace = "http://www.w3.org/2001/XMLSchema-instance")
        @schema_location = schema_location
        @prefix = prefix
        @namespace = namespace
      end

      def to_xml_attributes
        {
          "xmlns:#{prefix}" => namespace,
          "#{prefix}:schemaLocation" => schema_location,
        }
      end
    end
  end
end
