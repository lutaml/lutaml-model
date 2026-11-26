# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"
require "lutaml/lml/executor"

RSpec.describe Lutaml::Lml::Executor::AdapterHelpers do
  # Use a lightweight host class so we can test the helpers in isolation.
  # The helpers operate on objects with a `.name` accessor and a `.value`
  # accessor (i.e. the TopElementAttribute interface), so a Struct is
  # sufficient and avoids coupling to model setup.
  let(:host) do
    Class.new do
      extend Lutaml::Lml::Executor::AdapterHelpers
    end
  end

  Attr = Struct.new(:name, :value, keyword_init: true)

  describe "#resolve_target_class" do
    it "returns the compiled class named by the map_to attribute" do
      compiled = { "Product" => String }
      attributes = [Attr.new(name: "map_to", value: "Product")]
      expect(host.resolve_target_class(attributes, compiled)).to eq(String)
    end

    it "returns nil when map_to is absent" do
      compiled = { "Product" => String }
      attributes = [Attr.new(name: "where", value: "/x")]
      expect(host.resolve_target_class(attributes, compiled)).to be_nil
    end

    it "returns nil when the named class is not compiled" do
      compiled = {}
      attributes = [Attr.new(name: "map_to", value: "Missing")]
      expect(host.resolve_target_class(attributes, compiled)).to be_nil
    end

    it "returns nil when attributes is nil" do
      expect(host.resolve_target_class(nil, {})).to be_nil
    end
  end

  describe "#attribute_value" do
    it "returns the string value of the named attribute" do
      attributes = [Attr.new(name: "where", value: "/Products/Product")]
      expect(host.attribute_value(attributes, "where")).to eq("/Products/Product")
    end

    it "returns nil when the attribute is absent" do
      attributes = [Attr.new(name: "other", value: "x")]
      expect(host.attribute_value(attributes, "where")).to be_nil
    end

    it "returns nil when attributes is nil" do
      expect(host.attribute_value(nil, "where")).to be_nil
    end

    it "stringifies non-string values" do
      attributes = [Attr.new(name: "indent", value: true)]
      expect(host.attribute_value(attributes, "indent")).to eq("true")
    end
  end

  describe "#find_attribute" do
    it "returns the matching attribute object" do
      target = Attr.new(name: "where", value: "/x")
      attributes = [Attr.new(name: "map_to", value: "X"), target]
      expect(host.find_attribute(attributes, "where")).to eq(target)
    end

    it "returns nil when no match" do
      attributes = [Attr.new(name: "map_to", value: "X")]
      expect(host.find_attribute(attributes, "where")).to be_nil
    end
  end

  describe "#find_class_for_instance" do
    let(:product_class) { Class.new }
    let(:order_class) { Class.new }
    let(:compiled) do
      { "Product" => product_class, "Order" => order_class }
    end

    it "returns [name, klass] for the matching class" do
      instance = product_class.new
      result = host.find_class_for_instance(instance, compiled)
      expect(result).to eq(["Product", product_class])
    end

    it "returns nil when no class matches" do
      instance = Object.new
      expect(host.find_class_for_instance(instance, compiled)).to be_nil
    end
  end
end
