# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation do
  let(:registry) { Lutaml::Model::Validation.new_registry } # rubocop:disable RSpec/DescribedClass

  describe Lutaml::Model::Validation::Issue do
    subject(:issue) do
      described_class.new(
        severity: "error",
        code: "TEST-001",
        message: "Something is wrong",
        location: "file.xml",
        line: 42,
        suggestion: "Fix it",
      )
    end

    it "serializes to JSON" do
      json = issue.to_json
      parsed = JSON.parse(json)
      expect(parsed["severity"]).to eq("error")
      expect(parsed["code"]).to eq("TEST-001")
      expect(parsed["message"]).to eq("Something is wrong")
      expect(parsed["location"]).to eq("file.xml")
      expect(parsed["line"]).to eq(42)
      expect(parsed["suggestion"]).to eq("Fix it")
    end

    it "returns correct severity predicates" do
      expect(issue).to be_error
      expect(issue).not_to be_warning
      expect(issue).not_to be_info
      expect(issue).not_to be_notice
    end

    it "round-trips through JSON" do
      json = issue.to_json
      restored = described_class.from_json(json)
      expect(restored.code).to eq("TEST-001")
      expect(restored.message).to eq("Something is wrong")
    end
  end

  describe Lutaml::Model::Validation::LayerResult do
    subject(:layer) do
      described_class.new(
        name: "Structure",
        status: "fail",
        duration_ms: 15,
        issues: [issue],
      )
    end

    let(:issue) do
      Lutaml::Model::Validation::Issue.new(
        severity: "warning",
        code: "TEST-002",
        message: "Minor issue",
      )
    end

    it "serializes to JSON" do
      json = layer.to_json
      parsed = JSON.parse(json)
      expect(parsed["name"]).to eq("Structure")
      expect(parsed["status"]).to eq("fail")
      expect(parsed["issues"].length).to eq(1)
    end

    it "filters issues by severity" do
      expect(layer.warnings.length).to eq(1)
      expect(layer.errors.length).to eq(0)
    end
  end

  describe Lutaml::Model::Validation::Report do
    subject(:report) do
      described_class.new(
        source: "test.xml",
        valid: false,
        duration_ms: 50,
        layers: [layer],
      )
    end

    let(:issue) do
      Lutaml::Model::Validation::Issue.new(
        severity: "error",
        code: "TEST-003",
        message: "Broken",
      )
    end

    let(:layer) do
      Lutaml::Model::Validation::LayerResult.new(
        name: "Check",
        status: "fail",
        issues: [issue],
      )
    end

    it "serializes to JSON" do
      json = report.to_json
      parsed = JSON.parse(json)
      expect(parsed["source"]).to eq("test.xml")
      expect(parsed["valid"]).to be(false)
      expect(parsed["timestamp"]).not_to be_nil
    end

    it "aggregates all issues" do
      expect(report.all_issues.length).to eq(1)
      expect(report.all_errors.length).to eq(1)
    end
  end

  describe Lutaml::Model::Validation::Rule do
    subject(:rule) { described_class.new }

    it "has default values" do
      expect(rule.code).to be_nil
      expect(rule.category).to eq(:general)
      expect(rule.severity).to eq("error")
      expect(rule.applicable?(nil)).to be true
      expect(rule.check(nil)).to eq([])
    end

    context "with a custom subclass" do
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
    end
  end

  describe Lutaml::Model::Validation::Registry do
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
      expect(rules.first.code).to eq("REG-001")
    end

    it "prevents duplicate registration" do
      registry.register(rule_class)
      expect(registry.size).to eq(1)
    end

    it "filters by category" do
      rules = registry.for_category(:test)
      expect(rules.length).to eq(1)
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
    end

    it "returns rule classes" do
      classes = registry.rule_classes
      expect(classes).to eq([rule_class])
    end
  end

  describe Lutaml::Model::Validation::Profile do
    let(:profile) do
      described_class.new(
        name: "basic",
        description: "Basic checks",
        rule_names: ["TestRule"],
      )
    end

    it "stores profile attributes" do
      expect(profile.name).to eq("basic")
      expect(profile.rule_names).to eq(["TestRule"])
    end

    context "with imports" do
      let(:base_rule_class) do
        Class.new(Lutaml::Model::Validation::Rule) do
          def self.name = "BaseRule"
          def code = "BASE-001"
        end
      end

      let(:extra_rule_class) do
        Class.new(Lutaml::Model::Validation::Rule) do
          def self.name = "ExtraRule"
          def code = "EXTRA-001"
        end
      end

      let(:base_profile) do
        described_class.new(
          name: "base",
          rule_names: ["BaseRule"],
        )
      end

      let(:extended_profile) do
        described_class.new(
          name: "extended",
          rule_names: ["ExtraRule"],
          imports: ["base"],
        )
      end

      it "resolves imports" do
        registry.register(base_rule_class)
        registry.register(extra_rule_class)
        profiles = { "base" => base_profile, "extended" => extended_profile }

        rules = extended_profile.resolve(registry, profiles)
        codes = rules.map(&:code)
        expect(codes).to include("BASE-001", "EXTRA-001")
      end
    end
  end

  describe Lutaml::Model::Validation::Context do
    subject(:context) { described_class.new }

    it "accumulates errors" do
      issue = Lutaml::Model::Validation::Issue.new(
        severity: "error", code: "T-001", message: "bad",
      )
      context.add_error(issue)
      expect(context.errors.length).to eq(1)
    end

    it "provides per-rule state" do
      state = context.rule_state("R-001")
      state[:count] = 5
      expect(context.rule_state("R-001")[:count]).to eq(5)
    end

    it "resets" do
      context.add_error(double("issue"))
      context.reset!
      expect(context.errors).to be_empty
    end
  end

  describe "end-to-end validation" do
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

    it "finds no issues with valid data" do
      ctx = { items: (1..50).to_a }
      issues = described_class.validate(ctx, registry)
      expect(issues).to be_empty
    end

    it "finds errors for empty items" do
      ctx = { items: [] }
      issues = described_class.validate(ctx, registry)
      expect(issues.length).to eq(1)
      expect(issues.first.code).to eq("E2E-001")
      expect(issues.first).to be_error
    end

    it "finds warnings for too many items" do
      ctx = { items: (1..101).to_a }
      issues = described_class.validate(ctx, registry)
      expect(issues.length).to eq(1)
      expect(issues.first.code).to eq("E2E-002")
      expect(issues.first).to be_warning
    end

    it "raises on validate! when errors exist" do
      ctx = { items: [] }
      expect do
        described_class.validate!(ctx, registry)
      end.to raise_error(Lutaml::Model::Validation::ValidationError, /E2E-001/)
    end

    it "does not raise on validate! when only warnings" do
      ctx = { items: (1..101).to_a }
      expect do
        described_class.validate!(ctx, registry)
      end.not_to raise_error
    end
  end
end
