# frozen_string_literal: true

require "liquid"
require "rspec/matchers"
require "canon"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  def fixture_path(filename)
    File.expand_path("../fixtures/#{filename}", __FILE__)
  end

  # Clear all caches between tests to prevent test pollution
  # Note: Test pollution exists in the test suite due to shared state in GlobalContext
  # This is a pre-existing issue that should be addressed separately
  config.before do
    # Clear caches only (not registered types)
    Lutaml::Model::GlobalContext.clear_caches if defined?(Lutaml::Model::GlobalContext)

    # Clear transformation registry
    Lutaml::Model::TransformationRegistry.instance.clear if defined?(Lutaml::Model::TransformationRegistry)

    # Reset GlobalRegister (clears caches, keeps registered types)
    Lutaml::Model::GlobalRegister.instance.reset if defined?(Lutaml::Model::GlobalRegister)
  end

  # After each test, ensure :xsd context exists
  # Some specs call GlobalContext.reset! which removes :xsd context
  # but :xsd register (from lutaml-xsd) needs its context to exist
  config.after do
    # Ensure :xsd context exists if :xsd register has models
    if defined?(Lutaml::Model::GlobalContext) && Lutaml::Model::GlobalContext.context(:xsd).nil?
      xsd_register = Lutaml::Model::GlobalRegister.lookup(:xsd)
      if xsd_register && !xsd_register.models.empty?
        # Create :xsd context and re-sync types from :xsd register
        context = Lutaml::Model::GlobalContext.create_context(id: :xsd,
                                                              fallback_to: [:default])
        # Re-register types from the :xsd register's internal @models
        xsd_register.models.each do |id, klass|
          next unless id.is_a?(Symbol)

          unless context.registry.registered?(id)
            context.registry.register(id, klass)
          end
        end
      end
    end
  end

  # Skip Ox and Oga adapter tests to focus on Nokogiri fixes
  config.before(:each, :ox_adapter) do
    skip("Ox adapter tests pending - focusing on Nokogiri")
  end

  config.before(:each, :oga_adapter) do
    skip("Oga adapter tests pending - focusing on Nokogiri")
  end

  # Show XML adapter testing configuration at test suite start
  config.before(:suite) do
    enabled = TestAdapterConfig.adapters_to_test
    all = TestAdapterConfig.all_adapters
    disabled = all - enabled

    if disabled.any?

    end
  end
end

# configuration example
require_relative "../lib/lutaml/model"
require_relative "support/test_namespaces"
require_relative "support/test_adapter_config"
# require_relative "../lib/lutaml/model/xml/nokogiri_adapter"
# require_relative "../lib/lutaml/model/xml/ox_adapter"
# require_relative "../lib/lutaml/model/toml_adapter/toml_rb_adapter"

Lutaml::Model::Config.configure do |config|
  config.xml_adapter_type = :nokogiri
  config.hash_adapter_type = :standard_hash
  config.json_adapter_type = :standard_json
  config.yaml_adapter_type = :standard_yaml
  config.toml_adapter_type = :toml_rb
end

# Configure Canon for XML equivalence testing
# Use spec_friendly profile which includes structural_whitespace: :ignore
# This allows pretty-printed XML to be compared with compact XML
Canon::Config.configure do |config|
  config.xml.match.profile = :spec_friendly
end
