# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::Instance do
  describe "attributes" do
    it "has type attribute" do
      inst = described_class.new
      expect(inst.type).to be_nil
      inst.type = "MyClass"
      expect(inst.type).to eq("MyClass")
    end

    it "has attributes collection" do
      inst = described_class.new
      expect(inst.attributes).to be_nil
    end

    it "has nested instance" do
      inst = described_class.new
      expect(inst.instance).to be_nil
    end

    it "has template collection" do
      inst = described_class.new
      expect(inst.template).to be_nil
    end

    it "has parent attribute" do
      inst = described_class.new
      expect(inst.parent).to be_nil
      inst.parent = "base_product"
      expect(inst.parent).to eq("base_product")
    end
  end

  describe "nested instances" do
    it "allows deeply nested instances" do
      inner = described_class.new(type: "Inner")
      outer = described_class.new(type: "Outer", instance: inner)
      expect(outer.instance.type).to eq("Inner")
    end
  end

  describe "with attributes" do
    let(:inst) do
      attr1 = Lutaml::Lml::TopElementAttribute.new(name: "foo", type: "String")
      attr2 = Lutaml::Lml::TopElementAttribute.new(name: "bar", type: "Integer")
      described_class.new(type: "Product", attributes: [attr1, attr2])
    end

    it "holds typed attributes" do
      expect(inst.attributes.length).to eq(2)
      expect(inst.attributes.map(&:name)).to eq(%w[foo bar])
    end
  end

  describe "#each_attribute" do
    it "yields (name, value, nested) triplets for each attribute" do
      nested = described_class.new(type: "Child")
      child_attr = Lutaml::Lml::TopElementAttribute.new(
        name: "items", type: "Item", instances: [nested],
      )
      scalar_attr = Lutaml::Lml::TopElementAttribute.new(
        name: "count", type: "Integer", value: 3,
      )
      inst = described_class.new(attributes: [child_attr, scalar_attr])

      triplets = []
      inst.each_attribute { |*t| triplets << t }

      expect(triplets).to eq([["items", nil, [nested]], ["count", 3, []]])
    end

    it "returns an Enumerator when no block is given" do
      inst = described_class.new
      expect(inst.each_attribute).to be_an(Enumerator)
    end
  end
end
