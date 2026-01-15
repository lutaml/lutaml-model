# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/xml/decisions/decision"

RSpec.describe Lutaml::Model::Xml::Decisions::Decision do
  let(:namespace_class) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://example.com/ns"
      prefix_default "ex"
    end
  end

  describe ".prefix" do
    it "creates a prefix format decision" do
      decision = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "Explicit option"
      )

      expect(decision.format).to eq(:prefix)
      expect(decision.prefix).to eq("ex")
      expect(decision.namespace_class).to eq(namespace_class)
      expect(decision.reason).to eq("Explicit option")
    end
  end

  describe ".default" do
    it "creates a default format decision" do
      decision = described_class.default(
        namespace_class: namespace_class,
        reason: "Element form default"
      )

      expect(decision.format).to eq(:default)
      expect(decision.prefix).to be_nil
      expect(decision.namespace_class).to eq(namespace_class)
      expect(decision.reason).to eq("Element form default")
    end
  end

  describe "#uses_prefix?" do
    it "returns true for prefix format" do
      decision = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "test"
      )

      expect(decision.uses_prefix?).to be true
    end

    it "returns false for default format" do
      decision = described_class.default(
        namespace_class: namespace_class,
        reason: "test"
      )

      expect(decision.uses_prefix?).to be false
    end
  end

  describe "#uses_default?" do
    it "returns false for prefix format" do
      decision = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "test"
      )

      expect(decision.uses_default?).to be false
    end

    it "returns true for default format" do
      decision = described_class.default(
        namespace_class: namespace_class,
        reason: "test"
      )

      expect(decision.uses_default?).to be true
    end
  end

  describe "#==" do
    it "returns true for equal decisions" do
      decision1 = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "test"
      )

      decision2 = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "different reason"
      )

      expect(decision1).to eq(decision2)
    end

    it "returns false for different namespace_class" do
      other_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://other.com/ns"
        prefix_default "other"
      end

      decision1 = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "test"
      )

      decision2 = described_class.prefix(
        prefix: "ex",
        namespace_class: other_ns,
        reason: "test"
      )

      expect(decision1).not_to eq(decision2)
    end

    it "returns false for different format" do
      decision1 = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "test"
      )

      decision2 = described_class.default(
        namespace_class: namespace_class,
        reason: "test"
      )

      expect(decision1).not_to eq(decision2)
    end

    it "returns false for different prefix" do
      decision1 = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "test"
      )

      decision2 = described_class.prefix(
        prefix: "ex2",
        namespace_class: namespace_class,
        reason: "test"
      )

      expect(decision1).not_to eq(decision2)
    end
  end

  describe "#initialize" do
    it "validates format is :prefix or :default" do
      expect {
        described_class.new(format: :invalid, prefix: "ex", namespace_class: namespace_class)
      }.to raise_error(ArgumentError, "Format must be :prefix or :default")
    end

    it "validates prefix is required for :prefix format" do
      expect {
        described_class.new(format: :prefix, prefix: nil, namespace_class: namespace_class)
      }.to raise_error(ArgumentError, "Prefix required for :prefix format")
    end

    it "validates prefix must be nil for :default format" do
      expect {
        described_class.new(format: :default, prefix: "ex", namespace_class: namespace_class)
      }.to raise_error(ArgumentError, "Prefix must be nil for :default format")
    end
  end

  describe "#to_s" do
    it "returns string representation for prefix format" do
      decision = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "test reason"
      )

      str = decision.to_s
      expect(str).to include("format=prefix")
      expect(str).to include("prefix=ex")
      expect(str).to include("reason=test reason")
    end

    it "returns string representation for default format" do
      decision = described_class.default(
        namespace_class: namespace_class,
        reason: "test reason"
      )

      str = decision.to_s
      expect(str).to include("format=default")
      expect(str).to include("reason=test reason")
    end
  end

  describe "immutability" do
    it "is frozen" do
      decision = described_class.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "test"
      )

      expect(decision).to be_frozen
    end
  end
end
