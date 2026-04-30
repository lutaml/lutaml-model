# frozen_string_literal: true

module Lutaml
  module Xml
    # Adapter loader for XML format.
    #
    # Handles XML-specific adapter file loading and class resolution.
    # Registered with FormatRegistry so Configuration can delegate
    # XML adapter loading without hardcoded XML references.
    module AdapterLoader
      # Load the XML adapter file
      #
      # @param _adapter [String] The adapter format name ("xml")
      # @param type [String] The normalized type name (e.g., "nokogiri_adapter")
      def self.load_adapter_file(_adapter, type)
        adapter_path = if Lutaml::Model::RuntimeCompatibility.opal?
                         "lutaml/xml/adapter/#{type}"
                       else
                         File.join(File.dirname(__FILE__), "adapter", type)
                       end
        require adapter_path
      rescue LoadError
        raise Lutaml::Model::UnknownAdapterTypeError.new("xml", type),
              cause: nil
      end

      # Load the Moxml adapter for XML
      #
      # @param type_name [Symbol] The adapter type (:nokogiri, :ox, etc.)
      # @param _adapter_name [Symbol] The format name (:xml)
      def self.load_moxml_adapter(type_name, _adapter_name)
        Moxml::Adapter.load(type_name)
      end

      # Resolve the adapter class for XML
      #
      # @param _adapter [String] The adapter format name ("xml")
      # @param type [String] The normalized type name (e.g., "nokogiri_adapter")
      # @return [Class] The adapter class
      def self.class_for(_adapter, type)
        Lutaml::Xml::Adapter.const_get(to_class_name(type))
      end

      # Convert string to class name
      #
      # @param str [String] The string to convert
      # @return [String] The class name
      def self.to_class_name(str)
        str.to_s.split("_").map(&:capitalize).join
      end
    end
  end
end
