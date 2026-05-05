# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::Rule do
  subject(:rule) { described_class.new }

  describe "defaults" do
    it "returns nil code" do
      expect(rule.code).to be_nil
    end

    it "returns :general category" do
      expect(rule.category).to eq(:general)
    end

    it "returns error severity" do
      expect(rule.severity).to eq("error")
    end

    it "is always applicable" do
      expect(rule.applicable?(nil)).to be true
      expect(rule.applicable?({})).to be true
    end

    it "returns empty issues from check" do
      expect(rule.check(nil)).to eq([])
    end

    it "is not deferred" do
      expect(rule.needs_deferred?).to be false
    end

    it "returns empty array from complete" do
      expect(rule.complete(nil)).to eq([])
    end
  end

  describe "custom subclass" do
    let(:custom_rule_class) do
      Class.new(described_class) do
        def code = "CUSTOM-001"
        def category = :custom
        def severity = "warning"

        def applicable?(context)
          context&.dig(:enabled) != false
        end

        def check(_context)
          [issue("Found a problem")]
        end
      end
    end

    it "overrides defaults" do
      rule = custom_rule_class.new
      expect(rule.code).to eq("CUSTOM-001")
      expect(rule.category).to eq(:custom)
      expect(rule.severity).to eq("warning")
    end

    it "produces issues via helper" do
      rule = custom_rule_class.new
      issues = rule.check(nil)
      expect(issues.length).to eq(1)
      expect(issues.first.code).to eq("CUSTOM-001")
      expect(issues.first.severity).to eq("warning")
      expect(issues.first.message).to eq("Found a problem")
    end

    it "respects applicable?" do
      rule = custom_rule_class.new
      expect(rule.applicable?({ enabled: true })).to be true
      expect(rule.applicable?({ enabled: false })).to be false
    end

    it "allows issue helper to override severity and code" do
      klass = Class.new(described_class) do
        def code = "OVERRIDE"
        def severity = "error"

        def check(_context)
          [issue("msg", severity: "info", code: "OTHER")]
        end
      end
      issues = klass.new.check(nil)
      expect(issues.first.severity).to eq("info")
      expect(issues.first.code).to eq("OTHER")
    end
  end
end
