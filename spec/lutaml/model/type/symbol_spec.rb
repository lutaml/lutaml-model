require "spec_helper"

RSpec.describe Lutaml::Model::Type::Symbol do
  describe ".cast" do
    subject(:cast) { described_class.cast(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with symbol value" do
      let(:value) { :test }

      it { is_expected.to eq(:test) }
    end

    context "with string value" do
      let(:value) { "symbol" }

      it { is_expected.to eq(:symbol) }
    end

    context "with wrapped symbol format (:symbol:)" do
      let(:value) { ":test_symbol:" }

      it { is_expected.to eq(:test_symbol) }
    end

    context "with hash" do
      let(:value) { { a: 1, b: 2 } }

      it { is_expected.to eq(:"{:a=>1, :b=>2}") }
    end

    context "with empty string" do
      let(:value) { "" }

      it { is_expected.to be_nil }
    end

    context "with string containing whitespace" do
      let(:value) { ":hello world:" }

      it { is_expected.to eq(:"hello world") }
    end

    context "with string containing colon" do
      let(:value) { ":foo:bar:" }

      it { is_expected.to eq(:"foo:bar") }
    end
  end

  describe ".serialize" do
    it "returns nil for nil input" do
      expect(described_class.serialize(nil)).to be_nil
    end

    it "returns symbol for symbol input" do
      expect(described_class.serialize(:test)).to eq(:test)
    end

    it "returns symbol for string input" do
      expect(described_class.serialize("test")).to eq(:test)
    end

    it "returns symbol for wrapped format input" do
      expect(described_class.serialize(":test:")).to eq(:test)
    end
  end

  describe "format-specific methods" do
    let(:symbol_instance) { described_class.new(:test_symbol) }

    describe "#to_xml" do
      it "returns wrapped format" do
        expect(symbol_instance.to_xml).to eq(":test_symbol:")
      end
    end

    describe "#to_json" do
      it "returns wrapped format" do
        expect(symbol_instance.to_json).to eq(":test_symbol:")
      end
    end

    describe "#to_yaml" do
      it "returns the actual symbol" do
        expect(symbol_instance.to_yaml).to eq(:test_symbol)
      end
    end

    describe "#to_toml" do
      it "returns wrapped format" do
        expect(symbol_instance.to_toml).to eq(":test_symbol:")
      end
    end

    describe "#to_s" do
      it "returns string representation without quotes" do
        expect(symbol_instance.to_s).to eq("test_symbol")
      end
    end
  end

  describe "from format methods" do
    describe ".from_xml" do
      it "parses wrapped format" do
        expect(described_class.from_xml(":test:")).to eq(:test)
      end

      it "parses regular string" do
        expect(described_class.from_xml("test")).to eq(:test)
      end
    end

    describe ".from_json" do
      it "parses wrapped format" do
        expect(described_class.from_json(":test:")).to eq(:test)
      end

      it "parses regular string" do
        expect(described_class.from_json("test")).to eq(:test)
      end
    end

    describe ".from_yaml" do
      it "parses actual symbol" do
        expect(described_class.from_yaml(:test)).to eq(:test)
      end

      it "parses wrapped format" do
        expect(described_class.from_yaml(":test:")).to eq(:test)
      end

      it "parses regular string" do
        expect(described_class.from_yaml("test")).to eq(:test)
      end
    end

    describe ".from_toml" do
      it "parses wrapped format" do
        expect(described_class.from_toml(":test:")).to eq(:test)
      end

      it "parses regular string" do
        expect(described_class.from_toml("test")).to eq(:test)
      end
    end
  end

  describe "integration with serializable models" do
    let(:test_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :status, :symbol
        attribute :name, :string

        xml do
          root "test"
          map_element "status", to: :status
          map_element "name", to: :name
        end

        json do
          map "status", to: :status
          map "name", to: :name
        end

        yaml do
          map "status", to: :status
          map "name", to: :name
        end
      end
    end

    let(:instance) { test_class.new(status: :active, name: "Test") }

    describe "XML serialization" do
      it "serializes symbol correctly" do
        xml = instance.to_xml
        expect(xml).to include(":active:")
        expect(xml).to include("Test")
      end

      it "deserializes symbol correctly" do
        xml = <<~XML
          <test>
            <status>:pending:</status>
            <name>Test</name>
          </test>
        XML

        deserialized = test_class.from_xml(xml)
        expect(deserialized.status).to eq(:pending)
        expect(deserialized.name).to eq("Test")
      end
    end

    describe "JSON serialization" do
      it "serializes symbol correctly" do
        json = instance.to_json
        parsed = JSON.parse(json)
        expect(parsed["status"]).to eq(":active:")
        expect(parsed["name"]).to eq("Test")
      end

      it "deserializes symbol correctly" do
        json = '{"status":":inactive:","name":"Test"}'
        deserialized = test_class.from_json(json)
        expect(deserialized.status).to eq(:inactive)
        expect(deserialized.name).to eq("Test")
      end
    end

    describe "YAML serialization" do
      it "serializes symbol correctly" do
        yaml_hash = instance.to_yaml_hash
        expect(yaml_hash["status"]).to eq(:active)
        expect(yaml_hash["name"]).to eq("Test")
      end

      it "deserializes symbol correctly" do
        yaml = <<~YAML
          ---
          status: :completed
          name: Test
        YAML

        deserialized = test_class.from_yaml(yaml)
        expect(deserialized.status).to eq(:completed)
        expect(deserialized.name).to eq("Test")
      end
    end
  end
end
