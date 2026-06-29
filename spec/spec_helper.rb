# frozen_string_literal: true

require "liquid" unless RUBY_ENGINE == "opal"
require "rspec/matchers"
require "canon" unless RUBY_ENGINE == "opal"

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

  # Reset adapter state between adapter-switching tests
  config.after(:each, :adapter_test) do
    Lutaml::Model::AdapterScope.reset! if defined?(Lutaml::Model::AdapterScope)
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

  # Show XML adapter testing configuration at test suite start
  config.before(:suite) do
    enabled = TestAdapterConfig.adapters_to_test
    all = TestAdapterConfig.all_adapters
    disabled = all - enabled

    if disabled.any?

    end
  end

  # Under Opal, exclude specs that require native-only adapters,
  # filesystem, subprocess, schema compilation, or liquid templates.
  if RUBY_ENGINE == "opal"
    config.filter_run_excluding(
      :native_adapter,
      :native_fs,
      :subprocess,
      :performance,
      :examples,
      :consistency,
      :xsd_schema,
      :relaxng,
      :liquid,
    )
  end
end

# configuration example
require "lutaml/model"
require "lutaml/xml"
require_relative "support/test_namespaces"
require_relative "support/test_adapter_config"
# require_relative "../lib/lutaml/xml/adapter/nokogiri_adapter"
# require_relative "../lib/lutaml/xml/adapter/ox_adapter"
# require_relative "../lib/lutaml/model/toml_adapter/toml_rb_adapter"

Lutaml::Model::Config.configure do |config|
  config.xml_adapter_type  = RUBY_ENGINE == "opal" ? :oga : :nokogiri
  config.hash_adapter_type = :standard
  config.json_adapter_type = :standard
  config.yaml_adapter_type = :standard
  # toml_rb uses native ext; not registered as a lutaml format under Opal.
  config.toml_adapter_type = :toml_rb unless RUBY_ENGINE == "opal"
end

# Configure Canon for XML equivalence testing (Canon is not loaded under Opal)
if defined?(Canon::Config)
  Canon::Config.configure do |config|
    config.xml.match.profile = :spec_friendly
  end
end
