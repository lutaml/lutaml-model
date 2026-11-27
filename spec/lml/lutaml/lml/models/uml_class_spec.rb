# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::UmlClass do
  describe "attribute definitions" do
    it "has name attribute" do
      klass = described_class.new(name: "Widget")
      expect(klass.name).to eq("Widget")
    end

    it "has default visibility" do
      klass = described_class.new
      expect(klass.visibility).to eq("public")
    end

    it "has default is_abstract" do
      klass = described_class.new
      expect(klass.is_abstract).to be(false)
    end

    it "has collection attributes with defaults" do
      klass = described_class.new
      expect(klass.stereotype).to eq([])
      expect(klass.nested_classifier).to eq([])
    end
  end

  describe ".entity_type" do
    it "returns :classes" do
      expect(described_class.entity_type).to eq(:classes)
    end
  end

  describe "YAML serialization" do
    let(:klass) do
      described_class.new(
        name: "Person",
        definition: "A human being",
        is_abstract: true,
        stereotype: ["entity"],
        attributes: [
          Lutaml::Lml::TopElementAttribute.new(name: "name", type: "String"),
          Lutaml::Lml::TopElementAttribute.new(name: "age", type: "Integer"),
        ],
      )
    end

    it "round-trips through YAML" do
      yaml = klass.to_yaml
      restored = described_class.from_yaml(yaml)
      expect(restored.name).to eq("Person")
      expect(restored.is_abstract).to be(true)
    end

    it "infers owner_end in associations from_yaml" do
      yaml = <<~YAML
        name: Order
        associations:
          - name: items
            member_end: LineItem
      YAML

      restored = described_class.from_yaml(yaml)
      expect(restored.associations.length).to eq(1)
      expect(restored.associations[0].owner_end).to eq("Order")
    end
  end
end
