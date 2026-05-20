# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Rdf::MemberRule do
  describe ".new" do
    it "stores attr_name as symbol" do
      rule = described_class.new(:concepts)
      expect(rule.attr_name).to eq(:concepts)
    end

    it "converts string attr_name to symbol" do
      rule = described_class.new("concepts")
      expect(rule.attr_name).to eq(:concepts)
    end

    it "raises ArgumentError when predicate_name given without namespace" do
      expect do
        described_class.new(:items, predicate_name: :member)
      end.to raise_error(ArgumentError, /namespace is required/)
    end

    it "allows both predicate_name and namespace together" do
      rule = described_class.new(:items,
                                 predicate_name: :member,
                                 namespace: Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(rule.predicate_name).to eq(:member)
    end
  end

  describe "#linked?" do
    it "returns false when no predicate_name" do
      rule = described_class.new(:items)
      expect(rule.linked?).to be(false)
    end

    it "returns true when predicate_name is set" do
      rule = described_class.new(:items,
                                 predicate_name: :member,
                                 namespace: Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(rule.linked?).to be(true)
    end
  end

  describe "#linked_predicate_uri" do
    it "returns nil when no linking predicate" do
      rule = described_class.new(:items)
      expect(rule.linked_predicate_uri).to be_nil
    end

    it "resolves the linking predicate URI" do
      rule = described_class.new(:items,
                                 predicate_name: :member,
                                 namespace: Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(rule.linked_predicate_uri).to eq("http://www.w3.org/2004/02/skos/core#member")
    end
  end
end
