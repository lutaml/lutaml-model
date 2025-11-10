require "spec_helper"

RSpec.describe Lutaml::Model::RuleValueExtractor do
  subject(:extractor) do
    described_class.new(rule, doc, format, attr, register, options)
  end

  let(:rule) { instance_double(Lutaml::Model::Jsonl::MappingRule) }
  let(:doc) { { "name" => "Test", "value" => 123 } }
  let(:format) { :json }
  let(:attr) { instance_double(Lutaml::Model::Attribute) }
  let(:register) { instance_double(Lutaml::Model::Register) }
  let(:options) { {} }

  describe "#call" do
    context "when rule has single mapping" do
      before do
        allow(rule).to receive_messages(
          multiple_mappings?: false,
          name: "name",
          root_mapping?: false,
          raw_mapping?: false,
        )
      end

      it "returns value for the rule name" do
        expect(extractor.call).to eq("Test")
      end
    end

    context "when rule has multiple mappings" do
      before do
        allow(rule).to receive_messages(
          multiple_mappings?: true,
          name: ["name", "value"],
          root_mapping?: false,
          raw_mapping?: false,
        )
      end

      it "returns first initialized value" do
        expect(extractor.call).to eq("Test")
      end
    end

    context "when rule is root mapping" do
      before do
        allow(rule).to receive_messages(
          multiple_mappings?: false,
          name: "name",
          root_mapping?: true,
        )
      end

      it "returns the entire document" do
        expect(extractor.call).to eq(doc)
      end
    end

    context "when rule is raw mapping" do
      before do
        allow(rule).to receive_messages(
          multiple_mappings?: false,
          name: "name",
          root_mapping?: false,
          raw_mapping?: true,
        )
      end

      it "converts document to specified format" do
        expect(extractor.call).to eq('{"name":"Test","value":123}')
      end
    end

    context "when value is not found" do
      before do
        allow(rule).to receive_messages(
          multiple_mappings?: false,
          name: "nonexistent",
          root_mapping?: false,
          raw_mapping?: false,
        )
        allow(attr).to receive(:default_set?).with(register).and_return(false)
      end

      it "returns uninitialized value" do
        expect(extractor.call).to be_a(Lutaml::Model::UninitializedClass)
      end
    end

    context "when attribute has default value" do
      before do
        allow(rule).to receive_messages(
          multiple_mappings?: false,
          name: "nonexistent",
          root_mapping?: false,
          raw_mapping?: false,
        )
        allow(attr).to receive(:default_set?).with(register).and_return(true)
        allow(attr).to receive(:default).with(register).and_return("default_value")
      end

      it "returns default value" do
        expect(extractor.call).to eq("default_value")
      end
    end
  end

  describe "#uninitialized_value" do
    it "returns an instance of UninitializedClass" do
      expect(
        extractor.send(:uninitialized_value),
      ).to be_a(Lutaml::Model::UninitializedClass)
    end

    it "returns the same instance for multiple calls" do
      first_call = extractor.send(:uninitialized_value)
      second_call = extractor.send(:uninitialized_value)
      expect(first_call).to equal(second_call)
    end
  end
end
