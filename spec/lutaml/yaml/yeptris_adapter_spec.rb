# frozen_string_literal: true

require "spec_helper"
begin
  require "lutaml/yaml/adapter/yeptris_adapter"
rescue LoadError
  # yeptris ships no platform gem here (e.g. Windows): every example skips.
end

YEPTRIS_AVAILABLE = defined?(Yeptris)

RSpec.describe(YEPTRIS_AVAILABLE ? Lutaml::Yaml::Adapter::YeptrisAdapter : Object) do
  before { skip "yeptris is not available on this platform" unless YEPTRIS_AVAILABLE }

  let(:attributes) { { "name" => "John", "roles" => %w[admin dev] } }

  describe ".parse" do
    it "parses a YAML document into a hash" do
      expect(described_class.parse("name: John\nroles:\n  - admin\n  - dev\n"))
        .to eq(attributes)
    end

    it "round-trips nested structures" do
      yaml = described_class.parse("outer:\n  inner: 1\n")
      expect(yaml).to eq("outer" => { "inner" => 1 })
    end

    it "supports the same permitted classes as the standard adapter" do
      require "date"
      expect(described_class.parse("d: 2020-01-01\n"))
        .to eq("d" => Date.new(2020, 1, 1))
    end

    it "raises Psych::SyntaxError for invalid YAML, like the standard adapter" do
      expect { described_class.parse("name: test\n  invalid: [unclosed\n") }
        .to raise_error(Psych::SyntaxError)
    end

    it "raises Psych::SyntaxError for a mapping value inside a plain scalar" do
      # The dependent-CI shape: one line, a second "key:" colon after a
      # plain scalar run. Psych rejects it with "mapping values are not
      # allowed in this context"; the engine must surface under the
      # same class so downstream rescue ladders hold.
      expect { described_class.parse('name: test\n  invalid: [unclosed') }
        .to raise_error(Psych::SyntaxError)
    end

    it "carries the engine's position on the syntax error" do
      expect { described_class.parse("name: test\n  invalid: [unclosed\n") }
        .to raise_error(Psych::SyntaxError) do |error|
        expect(error.line).to be >= 1
        expect(error.problem).to be_a(String)
        expect(error.problem).not_to be_empty
        expect(error.message).to include("at line #{error.line}")
      end
    end
  end

  describe "#to_yaml" do
    subject(:document) { described_class.new(attributes) }

    it "serializes a hash to YAML that parses back identically" do
      expect(described_class.parse(document.to_yaml)).to eq(attributes)
    end
  end

  describe "round trip through a model" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :roles, :string, collection: true

        key_value do
          map "name", to: :name
          map "roles", to: :roles
        end
      end
    end

    it "deserializes and serializes via the yeptris engine" do
      model = model_class.from_yaml("name: John\nroles:\n  - admin\n  - dev\n")
      expect(model.name).to eq("John")
      expect(model.roles).to eq(%w[admin dev])
      expect(model_class.from_yaml(model.to_yaml).roles).to eq(%w[admin dev])
    end

    it "surfaces invalid YAML as InvalidFormatError" do
      expect { model_class.from_yaml("name: test\n  invalid: [unclosed\n") }
        .to raise_error(Lutaml::Model::InvalidFormatError)
    end
  end
end
