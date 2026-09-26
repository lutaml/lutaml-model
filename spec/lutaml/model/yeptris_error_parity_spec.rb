# frozen_string_literal: true

require "spec_helper"
require "shellwords"

# The suite deliberately never loads the optional yeptris engine
# in-process (adapter_resolver_configured_spec asserts the resolver's
# lazy-detection guarantee), so the error-class contract is exercised
# in a subprocess: wherever the engine is installed it is the
# preferred adapter, and its parse failures must surface under the
# standard adapters' error classes — Psych::SyntaxError and
# JSON::ParserError from the adapters, Lutaml::Model::InvalidFormatError
# through a model — so downstream rescue ladders hold on every engine.
RSpec.describe "yeptris adapter error parity" do
  subject(:outcomes) do
    `bundle exec ruby -e #{Shellwords.escape(probe)} 2>&1`
  end

  def yeptris_installed?
    Gem::Specification.find_by_name("yeptris")
    true
  rescue Gem::LoadError
    false
  end

  # The probe requires the engine explicitly (the resolved adapters
  # prove the preference), then reports one outcome line per surface.
  let(:probe) do
    <<~RUBY
      require "lutaml/model"

      def outcome
        yield
        "NO-ERROR"
      rescue StandardError => e
        "\#{e.class.name}: \#{e.message}"
      end

      puts "yaml-adapter: \#{Lutaml::Model::AdapterResolver.adapter_for(:yaml).name}"
      puts "json-adapter: \#{Lutaml::Model::AdapterResolver.adapter_for(:json).name}"

      puts "adapter-yaml: \#{outcome do
        Lutaml::Yaml::Adapter::YeptrisAdapter.parse("name: test\\n  invalid: [unclosed\\n")
      end }"
      puts "adapter-json: \#{outcome do
        Lutaml::Json::Adapter::YeptrisAdapter.parse("{nope")
      end }"

      model_class = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        key_value { map "name", to: :name }
      end
      puts "model-yaml: \#{outcome do
        model_class.from_yaml("name: test\\n  invalid: [unclosed\\n")
      end }"
      puts "model-json: \#{outcome do
        model_class.from_json("{nope")
      end }"
    RUBY
  end

  before { skip "yeptris is not installed" unless yeptris_installed? }

  it "prefers the yeptris adapters when the engine is installed" do
    expect(outcomes).to include("yaml-adapter: Lutaml::Yaml::Adapter::YeptrisAdapter")
    expect(outcomes).to include("json-adapter: Lutaml::Json::Adapter::YeptrisAdapter")
  end

  it "raises Psych::SyntaxError from the yaml adapter for invalid YAML" do
    expect(outcomes).to match(/^adapter-yaml: Psych::SyntaxError: .+ at line \d+/)
  end

  it "raises JSON::ParserError from the json adapter for invalid JSON" do
    expect(outcomes).to match(/^adapter-json: JSON::ParserError: /)
  end

  it "raises InvalidFormatError through a model for invalid YAML" do
    expect(outcomes).to match(/^model-yaml: Lutaml::Model::InvalidFormatError: /)
  end

  it "raises InvalidFormatError through a model for invalid JSON" do
    expect(outcomes).to match(/^model-json: Lutaml::Model::InvalidFormatError: /)
  end
end
