# frozen_string_literal: true

module Lutaml
  module Xml
    # Adapter loader for XML format.
    #
    # Every XML adapter type resolves to the ONE moxml adapter lane:
    # the file is shared, and the type symbol selects the ENGINE on
    # MoxmlAdapter (:moxml keeps the deferred call-time resolution).
    # Registered with FormatRegistry so Configuration can delegate
    # XML adapter loading without hardcoded XML references.
    module AdapterLoader
      # The one adapter file backing every XML type.
      ADAPTER_FILE = "moxml_adapter"

      # Load the XML adapter file
      #
      # @param _adapter [String] The adapter format name ("xml")
      # @param _type [String] The normalized type name (e.g.,
      #   "nokogiri_adapter") — informational; all types share the
      #   one adapter file
      def self.load_adapter_file(_adapter, _type)
        adapter_path = if Lutaml::Model.opal?
                         "lutaml/xml/adapter/#{ADAPTER_FILE}"
                       else
                         File.join(File.dirname(__FILE__), "adapter",
                                   ADAPTER_FILE)
                       end
        require adapter_path
      rescue LoadError => e
        raise Lutaml::Model::UnknownAdapterTypeError.new("xml", ADAPTER_FILE),
              cause: e
      end

      # Load the Moxml adapter for XML
      #
      # The engine preload for an explicit type pin: a missing engine
      # gem (e.g. no nokogiri in the Gemfile) surfaces here chained as
      # an UnknownAdapterTypeError, not as a bare LoadError.
      #
      # @param type_name [Symbol] The adapter type (:nokogiri, :ox, etc.)
      # @param _adapter_name [Symbol] The format name (:xml)
      def self.load_moxml_adapter(type_name, _adapter_name)
        # The deferred lane (#1224): :moxml names no engine - the
        # MoxmlAdapter class resolves the engine at call time, so
        # there is nothing to pre-load here.
        return if type_name.to_sym == :moxml

        Moxml::Adapter.load(type_name)
      rescue LoadError => e
        raise Lutaml::Model::UnknownAdapterTypeError.new("xml",
                                                         type_name),
              cause: e
      end

      # Resolve the adapter class for XML: the type symbol pins the
      # engine on the shared lane.
      #
      # @param _adapter [String] The adapter format name ("xml")
      # @param type [String] The normalized type name (e.g., "nokogiri_adapter")
      # @return [Class] The adapter class
      def self.class_for(_adapter, type)
        engine = type.to_s.delete_suffix("_adapter").to_sym
        Lutaml::Xml::Adapter::MoxmlAdapter.for_engine(engine)
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
