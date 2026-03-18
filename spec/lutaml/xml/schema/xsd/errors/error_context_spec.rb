# frozen_string_literal: true

require_relative "../spec_helper"
require "lutaml/xml/schema/xsd/errors/error_context"

RSpec.describe Lutaml::Xml::Schema::Xsd::Errors::ErrorContext do
  describe "#initialize" do
    it "creates context with all attributes" do
      context = described_class.new(
        location: "/root/element",
        namespace: "http://example.com",
        expected_type: "xs:string",
        actual_value: "123",
      )

      expect(context.location).to eq("/root/element")
      expect(context.namespace).to eq("http://example.com")
      expect(context.expected_type).to eq("xs:string")
      expect(context.actual_value).to eq("123")
    end

    it "stores additional attributes" do
      context = described_class.new(
        location: "/root",
        custom_field: "custom_value",
      )

      expect(context.additional).to eq({ custom_field: "custom_value" })
    end
  end

  describe "#to_h" do
    it "converts context to hash" do
      context = described_class.new(
        location: "/root/element",
        namespace: "http://example.com",
        expected_type: "xs:string",
        actual_value: "123",
      )

      hash = context.to_h
      expect(hash[:location]).to eq("/root/element")
      expect(hash[:namespace]).to eq("http://example.com")
      expect(hash[:expected_type]).to eq("xs:string")
      expect(hash[:actual_value]).to eq("123")
    end

    it "includes additional attributes" do
      context = described_class.new(
        location: "/root",
        custom: "value",
      )

      hash = context.to_h
      expect(hash[:custom]).to eq("value")
    end

    it "omits nil values" do
      context = described_class.new(location: "/root")

      hash = context.to_h
      expect(hash).to eq({ location: "/root" })
    end
  end
end
