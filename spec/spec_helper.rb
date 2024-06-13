# frozen_string_literal: true

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
end

# configuration example
require_relative "../lib/lutaml/model"
require_relative "../lib/lutaml/model/xml_adapter/nokogiri_adapter"
require_relative "../lib/lutaml/model/xml_adapter/ox_adapter"
require_relative "../lib/lutaml/model/xml_adapter/oga_adapter"
require_relative "../lib/lutaml/model/json_adapter/standard"
require_relative "../lib/lutaml/model/json_adapter/multi_json"
require_relative "../lib/lutaml/model/yaml_adapter"
require_relative "../lib/lutaml/model/toml_adapter/toml_rb_adapter"
require_relative "../lib/lutaml/model/toml_adapter/tomlib_adapter"

Lutaml::Model::Config.configure do |config|
  config.xml_adapter = Lutaml::Model::XmlAdapter::NokogiriDocument
  config.json_adapter = Lutaml::Model::JsonAdapter::StandardDocument
  config.yaml_adapter = Lutaml::Model::YamlAdapter::Standard
  config.toml_adapter = Lutaml::Model::TomlAdapter::TomlRbDocument
end
