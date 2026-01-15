# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/xml/decisions/element_prefix_resolver"
require "lutaml/model/xml/decisions/decision_engine"
require "lutaml/model/xml/decisions/decision_context"

RSpec.describe Lutaml::Model::Xml::Decisions::ElementPrefixResolver do
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

  describe "#initialize" do
    it "initializes with default engine" do
      resolver = described_class.new

      expect(resolver.engine).to be_a(Lutaml::Model::Xml::Decisions::DecisionEngine)
    end

    it "initializes with custom engine" do
      custom_engine = Lutaml::Model::Xml::Decisions::DecisionEngine.new([])
      resolver = described_class.new(custom_engine)

      expect(resolver.engine).to eq(custom_engine)
    end
  end

  describe "#resolve" do
    it "returns prefix for prefix format decision" do
      # Create a mock engine that returns prefix decision
      prefix_decision = Lutaml::Model::Xml::Decisions::Decision.prefix(
        prefix: "test",
        namespace_class: namespace_class,
        reason: "test"
      )

      mock_engine = instance_double("Lutaml::Model::Xml::Decisions::DecisionEngine")
      allow(mock_engine).to receive(:execute).and_return(prefix_decision)

      resolver = described_class.new(mock_engine)

      prefix = resolver.resolve(
        mock_element,
        mock_mapping,
        mock_needs,
        {}
      )

      expect(prefix).to eq("test")
    end

    it "returns nil for default format decision" do
      # Create a mock engine that returns default decision
      default_decision = Lutaml::Model::Xml::Decisions::Decision.default(
        namespace_class: namespace_class,
        reason: "test"
      )

      mock_engine = instance_double("Lutaml::Model::Xml::Decisions::DecisionEngine")
      allow(mock_engine).to receive(:execute).and_return(default_decision)

      resolver = described_class.new(mock_engine)

      prefix = resolver.resolve(
        mock_element,
        mock_mapping,
        mock_needs,
        {}
      )

      expect(prefix).to be_nil
    end

    it "passes all parameters to DecisionContext" do
      context_captured = nil

      # Capture the context passed to the engine
      mock_engine = instance_double("Lutaml::Model::Xml::Decisions::DecisionEngine")
      allow(mock_engine).to receive(:execute) do |context|
        context_captured = context
        Lutaml::Model::Xml::Decisions::Decision.default(
          namespace_class: namespace_class,
          reason: "test"
        )
      end

      resolver = described_class.new(mock_engine)

      resolver.resolve(
        mock_element,
        mock_mapping,
        mock_needs,
        { prefix: true },
        is_root: true,
        parent_format: :prefix,
        parent_namespace_class: namespace_class,
        parent_hoisted: { "ex" => "http://example.com/ns" }
      )

      expect(context_captured.element).to eq(mock_element)
      expect(context_captured.mapping).to eq(mock_mapping)
      expect(context_captured.needs).to eq(mock_needs)
      expect(context_captured.options).to eq({ prefix: true })
      expect(context_captured.is_root).to be true
      expect(context_captured.parent_format).to eq(:prefix)
      expect(context_captured.parent_namespace_class).to eq(namespace_class)
      expect(context_captured.parent_hoisted).to eq({ "ex" => "http://example.com/ns" })
    end
  end

  describe "#resolve_with_decision" do
    it "returns full Decision object" do
      expected_decision = Lutaml::Model::Xml::Decisions::Decision.prefix(
        prefix: "test",
        namespace_class: namespace_class,
        reason: "test reason"
      )

      mock_engine = instance_double("Lutaml::Model::Xml::Decisions::DecisionEngine")
      allow(mock_engine).to receive(:execute).and_return(expected_decision)

      resolver = described_class.new(mock_engine)

      decision = resolver.resolve_with_decision(
        mock_element,
        mock_mapping,
        mock_needs,
        {}
      )

      expect(decision).to eq(expected_decision)
      expect(decision.prefix).to eq("test")
      expect(decision.reason).to eq("test reason")
    end

    it "returns decision with format information" do
      prefix_decision = Lutaml::Model::Xml::Decisions::Decision.prefix(
        prefix: "ex",
        namespace_class: namespace_class,
        reason: "explicit option"
      )

      mock_engine = instance_double("Lutaml::Model::Xml::Decisions::DecisionEngine")
      allow(mock_engine).to receive(:execute).and_return(prefix_decision)

      resolver = described_class.new(mock_engine)

      decision = resolver.resolve_with_decision(
        mock_element,
        mock_mapping,
        mock_needs,
        { prefix: true }
      )

      expect(decision.format).to eq(:prefix)
      expect(decision.uses_prefix?).to be true
    end
  end

  describe "with default engine" do
    it "evaluates all decision rules in order" do
      # Use the default engine which has all rules
      resolver = described_class.new

      # The resolver should complete without error
      # Need to stub the NamespaceNeeds methods that are called by rules
      allow(mock_needs).to receive(:namespace).and_return(nil)
      allow(mock_needs).to receive(:scope_config_for).and_return(nil)

      expect {
        resolver.resolve(
          mock_element,
          mock_mapping,
          mock_needs,
          {}
        )
      }.not_to raise_error
    end
  end

  describe "immutability" do
    it "is frozen" do
      resolver = described_class.new
      expect(resolver).to be_frozen
    end
  end
end
