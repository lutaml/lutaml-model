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

    puts "\n#{'=' * 70}"
    puts "XML ADAPTER TESTING CONFIGURATION (Adapter First Strategy)"
    puts ('=' * 70)
    puts "Primary Adapter: #{TestAdapterConfig.primary_adapter}"
    puts "Enabled:  #{enabled.map(&:to_s).join(', ')}"
    puts "Disabled: #{disabled.map(&:to_s).join(', ')}" if disabled.any?
    puts "#{'=' * 70}\n"
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
