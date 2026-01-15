# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/xml/decisions/decision_engine"
require "lutaml/model/xml/decisions/decision_context"
require "lutaml/model/xml/decisions/decision_rule"

RSpec.describe Lutaml::Model::Xml::Decisions::DecisionEngine do
  let(:namespace_class) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://example.com/ns"
      prefix_default "ex"
    end
  end

  let(:mock_element) do
    instance_double("Lutaml::Model::XmlDataModel::XmlElement", namespace_class: namespace_class)
  end

  let(:mock_mapping) { instance_double("Lutaml::Model::Xml::Mapping") }
  let(:mock_needs) { instance_double("Lutaml::Model::Xml::NamespaceNeeds") }

  let(:context) do
    Lutaml::Model::Xml::Decisions::DecisionContext.new(
      element: mock_element,
      mapping: mock_mapping,
      needs: mock_needs,
      options: {}
    )
  end

  describe "#initialize" do
    it "sorts rules by priority" do
      low_priority_rule = Class.new(Lutaml::Model::Xml::Decisions::DecisionRule) do
        def priority
          10
        end

        def applies?(context)
          true
        end

        def decide(context)
          Lutaml::Model::Xml::Decisions::Decision.default(namespace_class: Object, reason: "low")
        end
      end.new

      high_priority_rule = Class.new(Lutaml::Model::Xml::Decisions::DecisionRule) do
        def priority
          1
        end

        def applies?(context)
          true
        end

        def decide(context)
          Lutaml::Model::Xml::Decisions::Decision.default(namespace_class: Object, reason: "high")
        end
      end.new

      engine = described_class.new([low_priority_rule, high_priority_rule])

      # Rules should be sorted by priority (high first)
      expect(engine.rules.first).to eq(high_priority_rule)
      expect(engine.rules.last).to eq(low_priority_rule)
    end
  end

  describe "#execute" do
    it "returns first applicable decision" do
      first_rule = Class.new(Lutaml::Model::Xml::Decisions::DecisionRule) do
        def priority
          1
        end

        def applies?(context)
          true
        end

        def decide(context)
          Lutaml::Model::Xml::Decisions::Decision.prefix(
            prefix: "first",
            namespace_class: Object,
            reason: "first rule"
          )
        end
      end.new

      second_rule = Class.new(Lutaml::Model::Xml::Decisions::DecisionRule) do
        def priority
          2
        end

        def applies?(context)
          true
        end

        def decide(context)
          Lutaml::Model::Xml::Decisions::Decision.prefix(
            prefix: "second",
            namespace_class: Object,
            reason: "second rule"
          )
        end
      end.new

      engine = described_class.new([first_rule, second_rule])
      decision = engine.execute(context)

      expect(decision.prefix).to eq("first")
      expect(decision.reason).to eq("first rule")
    end

    it "skips non-applicable rules" do
      non_applicable_rule = Class.new(Lutaml::Model::Xml::Decisions::DecisionRule) do
        def priority
          1
        end

        def applies?(context)
          false
        end

        def decide(context)
          raise "Should not be called"
        end
      end.new

      applicable_rule = Class.new(Lutaml::Model::Xml::Decisions::DecisionRule) do
        def priority
          2
        end

        def applies?(context)
          true
        end

        def decide(context)
          Lutaml::Model::Xml::Decisions::Decision.prefix(
            prefix: "applicable",
            namespace_class: Object,
            reason: "applicable rule"
          )
        end
      end.new

      engine = described_class.new([non_applicable_rule, applicable_rule])
      decision = engine.execute(context)

      expect(decision.prefix).to eq("applicable")
    end

    it "raises RuntimeError if no rule applies" do
      never_applies_rule = Class.new(Lutaml::Model::Xml::Decisions::DecisionRule) do
        def priority
          1
        end

        def applies?(context)
          false
        end

        def decide(context)
          raise "Should not be called"
        end
      end.new

      engine = described_class.new([never_applies_rule])

      expect {
        engine.execute(context)
      }.to raise_error(RuntimeError, /No decision rule applied/)
    end
  end

  describe ".default" do
    it "loads all 7+ default rules" do
      engine = described_class.default

      # Should have at least 7 default rules (8 including DefaultPreferenceRule)
      expect(engine.rules.size).to be >= 7
    end

    it "includes DefaultPreferenceRule as catch-all" do
      engine = described_class.default

      # Last rule should be DefaultPreferenceRule (catch-all)
      last_rule = engine.rules.last
      expect(last_rule.class.name).to include("DefaultPreferenceRule")
    end
  end

  describe "#add_rule" do
    it "returns new engine with rule added" do
      original_engine = described_class.new([])

      new_rule = Class.new(Lutaml::Model::Xml::Decisions::DecisionRule) do
        def priority
          5
        end

        def applies?(context)
          true
        end

        def decide(context)
          Lutaml::Model::Xml::Decisions::Decision.default(
            namespace_class: Object,
            reason: "new rule"
          )
        end
      end.new

      new_engine = original_engine.add_rule(new_rule)

      # Original engine should be unchanged (immutability)
      expect(original_engine.rules).to be_empty

      # New engine should have the rule
      expect(new_engine.rules).to include(new_rule)
    end
  end

  describe "immutability" do
    it "is frozen" do
      engine = described_class.new([])
      expect(engine).to be_frozen
    end
  end
end
