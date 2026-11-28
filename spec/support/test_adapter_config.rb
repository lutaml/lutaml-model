# frozen_string_literal: true

# Centralized configuration for XML adapter testing
#
# Implements Adapter First Strategy:
# - Start with primary adapter (Nokogiri)
# - Enable other adapters (Ox, Oga) incrementally once they pass full test suite
#
# Usage:
#   # Enable only Nokogiri (primary)
#   TestAdapterConfig.configure do |config|
#     config.enabled_adapters = [:nokogiri]
#   end
#
#   # Enable additional adapters when ready
#   TestAdapterConfig.configure do |config|
#     config.enabled_adapters = [:nokogiri, :ox]
#   end
class TestAdapterConfig
  # Primary adapter (focus on this first)
  PRIMARY_ADAPTER = :nokogiri

  class << self
    attr_accessor :enabled_adapters

    # Configure adapter testing
    # @yield [config] The configuration object
    def configure
      yield self
    end

    # Get the primary adapter name
    # @return [Symbol] The primary adapter name
    def primary_adapter
      PRIMARY_ADAPTER
    end

    # Get list of adapters to test
    # @return [Array<Symbol>] List of enabled adapter names
    def adapters_to_test
      @adapters_to_test ||= enabled_adapters || [PRIMARY_ADAPTER]
    end

    # Enable an adapter for testing
    # @param name [Symbol] Adapter name (:nokogiri, :ox, :oga)
    def enable_adapter(name)
      adapters_to_test << name unless adapters_to_test.include?(name)
    end

    # Check if an adapter is enabled for testing
    # @param name [Symbol] Adapter name
    # @return [Boolean] true if adapter is enabled
    def adapter_enabled?(name)
      adapters_to_test.include?(name)
    end

    # Get the adapter lane for an engine: the one moxml adapter
    # pinned to that engine.
    # @param name [Symbol] Engine name (:nokogiri, :ox, :oga, :rexml, :leptris)
    # @return [Class] The pinned adapter class
    def adapter_class(name)
      Lutaml::Xml::Adapter::MoxmlAdapter.for_engine(name)
    end

    # Get list of all available adapter names
    # @return [Array<Symbol>] List of all adapter names
    def all_adapters
      %i[nokogiri ox oga rexml]
    end

    # Get engine name by adapter class
    # @param klass [Class] Adapter class
    # @return [Symbol, nil] Engine name or nil if not the moxml adapter family
    def adapter_name(klass)
      klass.engine_name if klass.is_a?(Class) &&
        klass <= Lutaml::Xml::Adapter::MoxmlAdapter
    end
  end
end

# Initial configuration: Primary adapter (Nokogiri) only
# Enable other adapters (Ox, Oga) incrementally once they pass full test suite
TestAdapterConfig.configure do |config|
  config.enabled_adapters = %i[nokogiri oga]
end
