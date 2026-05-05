# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::Registry do
  subject(:registry) { described_class.new }

  let(:rule_class) do
    Class.new(Lutaml::Model::Validation::Rule) do
      def code = "REG-001"
      def category = :test
    end
  end

  before { registry.register(rule_class) }

  it "registers and returns rule instances" do
    rules = registry.all
    expect(rules.length).to eq(1)
    expect(rules.first).to be_a(rule_class)
    expect(rules.first.code).to eq("REG-001")
  end

  it "prevents duplicate registration" do
    registry.register(rule_class)
    expect(registry.size).to eq(1)
  end

  it "filters by category" do
    rules = registry.for_category(:test)
    expect(rules.length).to eq(1)
    expect(registry.for_category(:other)).to be_empty
  end

  it "finds by code" do
    rule = registry.find("REG-001")
    expect(rule).not_to be_nil
    expect(rule.code).to eq("REG-001")
  end

  it "returns nil for unknown code" do
    expect(registry.find("UNKNOWN")).to be_nil
  end

  it "resets" do
    registry.reset!
    expect(registry.size).to eq(0)
    expect(registry.all).to be_empty
  end

  it "returns rule classes" do
    expect(registry.rule_classes).to eq([rule_class])
  end

  it "returns a defensive copy of rule_classes" do
    classes = registry.rule_classes
    classes << String
    expect(registry.rule_classes.length).to eq(1)
  end
end
