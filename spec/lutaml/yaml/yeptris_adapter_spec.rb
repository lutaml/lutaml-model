# frozen_string_literal: true

require "lutaml/yaml/adapter/yeptris_adapter"

RSpec.describe Lutaml::Yaml::Adapter::YeptrisAdapter do
  before { skip "yeptris is not available on this platform" unless described_class.available? }

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

    # Dump parity with the standard adapter is the contract: a stored
    # fixture generated under one adapter must round-trip byte-exactly
    # under the other, or a host whose bundle flips the default engine
    # rewrites every stored YAML (relaton's SAE suite caught the
    # 0.8.171 default flip this way). Generation rides the native face
    # only when the adapter's capability probe (native_dump_parity?)
    # finds the engine byte-identical across the shape battery —
    # plain-scalar folding landed in yeptris 0.6.62.1, bare null keys
    # after literal blocks in 0.6.63 (leptris/yeptris#863, #1264);
    # engines that miss a shape keep the standard dump.
    describe "byte parity with the standard adapter" do
      let(:long_scalar) do
        "Taxonomy and Definitions for Terms Related to Driving Automation " \
          "Systems for On-Road Motor Vehicles for On-Road Motor Vehicles"
      end
      let(:wrapped_attributes) do
        { "title" => long_scalar, "roles" => %w[admin dev] }
      end

      # The same shapes the capability probe exercises in
      # yeptris_adapter.rb — keep the two lists in sync.
      let(:parity_shapes) do
        [
          wrapped_attributes,
          { "s" => "line1\nline2", "n" => nil },
          { "q" => "has: colon", "n" => nil },
          { "u" => "héllo wörld", "num" => "007", "f" => 1.5, "e" => "" },
          { "deep" => { "deeper" => [{ "x" => "y" }, [4, 5]] } },
          { "multi" => "para one\n\npara two", "dash" => "a - b - c",
            "omitted" => nil },
          { "a" => 1, "b" => [1, 2, 3], "c" => { "d" => true } },
        ]
      end

      it "dumps every parity shape byte-identically to the standard adapter" do
        parity_shapes.each do |shape|
          standard = Lutaml::Yaml::Adapter::StandardAdapter.new(shape).to_yaml
          expect(described_class.new(shape).to_yaml).to eq(standard)
        end
      end

      it "parses the standard adapter's dumps back identically" do
        parity_shapes.each do |shape|
          standard = Lutaml::Yaml::Adapter::StandardAdapter.new(shape).to_yaml
          expect(described_class.parse(standard)).to eq(shape)
        end
      end

      it "opens the native dump lane when the engine answers the probe" do
        skip "engine not fold-parity on this platform" unless
          described_class.native_dump_parity?

        first = parity_shapes.first
        expect(described_class.new(first).to_yaml)
          .to eq(Yeptris::Psych.dump(first))
      end
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
