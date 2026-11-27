# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::Association do
  describe "attribute definitions" do
    it "has name and definition" do
      assoc = described_class.new(name: "contains", definition: "Owner to member")
      expect(assoc.name).to eq("contains")
      expect(assoc.definition).to eq("Owner to member")
    end

    it "has default visibility" do
      assoc = described_class.new
      expect(assoc.visibility).to eq("public")
    end

    it "has owner and member ends" do
      assoc = described_class.new(
        owner_end: "Order",
        owner_end_type: "Order",
        member_end: "LineItem",
        member_end_type: "LineItem",
      )
      expect(assoc.owner_end).to eq("Order")
      expect(assoc.member_end).to eq("LineItem")
    end

    it "has cardinality ends" do
      card = Lutaml::Lml::Cardinality.new(min: "1", max: "*")
      assoc = described_class.new(
        owner_end: "Order",
        owner_end_cardinality: card,
      )
      expect(assoc.owner_end_cardinality.min).to eq("1")
      expect(assoc.owner_end_cardinality.max).to eq("*")
    end
  end
end
