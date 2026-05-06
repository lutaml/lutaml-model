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
  end
end
