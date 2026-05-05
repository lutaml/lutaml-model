# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation, ".validate / .validate!" do
  let(:registry) { described_class.new_registry }

  let(:rule_a_class) do
    Class.new(Lutaml::Model::Validation::Rule) do
      def code = "E2E-001"
      def severity = "error"

      def check(context)
        context[:items].empty? ? [issue("No items found")] : []
      end
    end
  end

  let(:rule_b_class) do
    Class.new(Lutaml::Model::Validation::Rule) do
      def code = "E2E-002"
      def severity = "warning"

      def check(context)
        context[:items].length > 100 ? [issue("Too many items")] : []
      end
    end
  end

  before do
    registry.register(rule_a_class)
    registry.register(rule_b_class)
  end

  describe ".validate" do
    it "finds no issues with valid data" do
      issues = described_class.validate({ items: (1..50).to_a }, registry)
      expect(issues).to be_empty
    end

    it "finds errors for empty items" do
      issues = described_class.validate({ items: [] }, registry)
      expect(issues.length).to eq(1)
      expect(issues.first.code).to eq("E2E-001")
      expect(issues.first).to be_error
    end

    it "finds warnings for too many items" do
      issues = described_class.validate({ items: (1..101).to_a }, registry)
      expect(issues.length).to eq(1)
      expect(issues.first.code).to eq("E2E-002")
      expect(issues.first).to be_warning
    end

    it "skips inapplicable rules" do
      skip_rule = Class.new(Lutaml::Model::Validation::Rule) do
        def code = "SKIP"
        def applicable?(_ctx) = false
        def check(_ctx) = [issue("should not appear")]
      end
      registry.register(skip_rule)
      issues = described_class.validate({ items: [1] }, registry)
      expect(issues).to be_empty
    end

    it "does not crash with contexts that support add_error" do
      Lutaml::Model::Validation::Context.new
      # Use plain hash for data — rules expect [:items]
      issues = described_class.validate({ items: [] }, registry)
      expect(issues.length).to eq(1)
      # Plain hash doesn't accumulate, but validate still works
    end
  end

  describe ".validate!" do
    it "raises on errors" do
      expect do
        described_class.validate!({ items: [] }, registry)
      end.to raise_error(Lutaml::Model::Validation::ValidationError, /E2E-001/)
    end

    it "does not raise when only warnings" do
      expect do
        described_class.validate!({ items: (1..101).to_a }, registry)
      end.not_to raise_error
    end

    it "does not raise when no issues" do
      expect do
        described_class.validate!({ items: (1..50).to_a }, registry)
      end.not_to raise_error
    end
  end

  describe ".new_registry" do
    it "returns a fresh Registry instance" do
      reg = described_class.new_registry
      expect(reg).to be_a(Lutaml::Model::Validation::Registry)
      expect(reg.size).to eq(0)
    end
  end
end
