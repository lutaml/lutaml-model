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
      @enabled_adapters ||= [PRIMARY_ADAPTER]
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

    # Get adapter class by name (lazy evaluation to avoid loading issues)
    # @param name [Symbol] Adapter name
    # @return [Class, nil] Adapter class or nil if not defined
    def adapter_class(name)
      case name
      when :nokogiri
        Lutaml::Model::Xml::NokogiriAdapter
      when :ox
        defined?(Lutaml::Model::Xml::OxAdapter) ? Lutaml::Model::Xml::OxAdapter : nil
      when :oga
        defined?(Lutaml::Model::Xml::OgaAdapter) ? Lutaml::Model::Xml::OgaAdapter : nil
      end
    end

    # Get list of all available adapter names
    # @return [Array<Symbol>] List of all adapter names
    def all_adapters
      [:nokogiri, :ox, :oga]
    end

    # Get adapter name by class
    # @param klass [Class] Adapter class
    # @return [Symbol, nil] Adapter name or nil if not found
    def adapter_name(klass)
      case klass
      when Lutaml::Model::Xml::NokogiriAdapter
        :nokogiri
      when Lutaml::Model::Xml::OxAdapter
        :ox
      when Lutaml::Model::Xml::OgaAdapter
        :oga
      else
        nil
      end
    end
  end
end

# Initial configuration: Primary adapter (Nokogiri) only
# Enable other adapters (Ox, Oga) incrementally once they pass full test suite
TestAdapterConfig.configure do |config|
  config.enabled_adapters = [:nokogiri]
end
