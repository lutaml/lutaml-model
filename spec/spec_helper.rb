# frozen_string_literal: true

# require "liquid"
require "rspec/matchers"
require "equivalent-xml"

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
end

# configuration example
require "lutaml/model"
# require_relative "../lib/lutaml/model/xml/nokogiri_adapter"
# require_relative "../lib/lutaml/model/xml/ox_adapter"
# require_relative "../lib/lutaml/model/toml_adapter/toml_rb_adapter"

Lutaml::Model::Config.configure do |config|
  if RUBY_ENGINE == 'opal'
    config.xml_adapter_type = :oga
  else
    config.xml_adapter_type = :nokogiri
  end
  config.hash_adapter_type = :standard_hash
  config.json_adapter_type = :standard_json
  config.yaml_adapter_type = :standard_yaml
  config.toml_adapter_type = :toml_rb unless RUBY_ENGINE == 'opal'
end

# Create a normalized string version for strings interpolating symbols for Opal
def sym_normal(str)
  if RUBY_ENGINE == 'opal'
    str.gsub(/:(\w+)/) { "\"#{$1}\"" }
  else
    str
  end
end
