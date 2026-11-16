# frozen_string_literal: true

module Lutaml
  module Yamls
    # Adapter loader for the YAMLS stream format.
    #
    # YAMLS adapters live in lutaml/yamls/adapter/, not the default
    # lutaml/key_value/adapter/<format>/ layout, so registration carries
    # this loader for AdapterResolver's file loading and class resolution.
    module AdapterLoader
      # Load the YAMLS adapter file
      #
      # @param _adapter [String] the adapter format name ("yamls")
      # @param type [String] the normalized type name (e.g., "yeptris_adapter")
      def self.load_adapter_file(_adapter, type)
        adapter_path = if Lutaml::Model.opal?
                         "lutaml/yamls/adapter/#{type}"
                       else
                         File.join(File.dirname(__FILE__), "adapter", type)
                       end
        require adapter_path
      rescue LoadError => e
        raise Lutaml::Model::UnknownAdapterTypeError.new("yamls", type),
              cause: e
      end

      # YAMLS is not an XML format; the resolver calls this on every
      # registered loader, so it is a no-op here.
      def self.load_moxml_adapter(_type_name, _adapter_name); end

      # Resolve the adapter class for YAMLS
      #
      # @param _adapter [String] the adapter format name ("yamls")
      # @param type [String] the normalized type name (e.g., "yeptris_adapter")
      # @return [Class] the adapter class
      def self.class_for(_adapter, type)
        Lutaml::Yamls::Adapter.const_get(to_class_name(type))
      end

      # Convert string to class name
      #
      # @param str [String] the string to convert
      # @return [String] the class name
      def self.to_class_name(str)
        str.to_s.split("_").map(&:capitalize).join
      end
    end
  end
end
