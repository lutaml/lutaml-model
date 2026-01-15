# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::Transformation do
  # Create a concrete transformation class for testing
  let(:test_transformation_class) do
    Class.new(described_class) do
      def transform(model_instance, options = {})
        "transformed_#{model_instance.class.name}"
      end

      private

      def compile_rules(mapping_dsl)
        # Return empty rules for now
        []
      end
    end
  end

  let(:model_class) do
    Class.new do
      def self.name
        "TestModel"
      end
    end
  end

  let(:mapping_dsl) { double("MappingDSL") }
  let(:format) { :xml }
  let(:register) { nil }

  describe "#initialize" do
    it "creates a new transformation instance" do
      transformation = test_transformation_class.new(
        model_class,
        mapping_dsl,
        format,
        register
      )

      expect(transformation.model_class).to eq(model_class)
      expect(transformation.format).to eq(format)
      expect(transformation.register).to eq(register)
      expect(transformation.compiled_rules).to eq([])
    end

    it "freezes the transformation after creation" do
      transformation = test_transformation_class.new(
        model_class,
        mapping_dsl,
        format,
        register
      )

      expect(transformation).to be_frozen
    end

    it "calls compile_rules during initialization" do
      transformation_class = Class.new(described_class) do
        attr_reader :compile_called

        def transform(model_instance, options = {}); end

        private

        def compile_rules(mapping_dsl)
          @compile_called = true
          []
        end
      end

      transformation = transformation_class.new(
        model_class,
        mapping_dsl,
        format,
        register
      )

      expect(transformation.instance_variable_get(:@compile_called)).to be true
    end
  end

  describe "#transform" do
    it "raises NotImplementedError when not overridden" do
      abstract_class = Class.new(described_class) do
        private

        def compile_rules(_mapping_dsl)
          []
        end
      end

      transformation = abstract_class.new(
        model_class,
        mapping_dsl,
        format,
        register
      )

      expect { transformation.transform(model_class.new) }
        .to raise_error(NotImplementedError, /transform must be implemented/)
    end

    it "can be overridden by subclasses" do
      transformation = test_transformation_class.new(
        model_class,
        mapping_dsl,
        format,
        register
      )

      result = transformation.transform(model_class.new)
      expect(result).to eq("transformed_TestModel")
    end
  end

  describe "#all_namespaces" do
    it "collects namespaces from all compiled rules" do
      ns_class = double("NamespaceClass")
      rule1 = double("Rule1", all_namespaces: [ns_class])
      rule2 = double("Rule2", all_namespaces: [ns_class])

      # Create a test class that returns specific rules
      test_class = Class.new(described_class) do
        attr_accessor :test_rules

        def transform(model_instance, options = {}); end

        private

        def compile_rules(_mapping_dsl)
          @test_rules || []
        end
      end

      instance = test_class.allocate
      instance.instance_variable_set(:@model_class, model_class)
      instance.instance_variable_set(:@format, format)
      instance.instance_variable_set(:@register, register)
      instance.instance_variable_set(:@compiled_rules, [rule1, rule2])
      instance.freeze

      namespaces = instance.all_namespaces
      expect(namespaces).to eq([ns_class])
    end

    it "returns unique namespaces" do
      ns_class = double("NamespaceClass")
      rule1 = double("Rule1", all_namespaces: [ns_class])
      rule2 = double("Rule2", all_namespaces: [ns_class])

      # Create instance with duplicate namespace references
      test_class = Class.new(described_class) do
        def transform(model_instance, options = {}); end

        private

        def compile_rules(_mapping_dsl)
          []
        end
      end

      instance = test_class.allocate
      instance.instance_variable_set(:@model_class, model_class)
      instance.instance_variable_set(:@format, format)
      instance.instance_variable_set(:@register, register)
      instance.instance_variable_set(:@compiled_rules, [rule1, rule2])
      instance.freeze

      namespaces = instance.all_namespaces
      # Should return unique namespaces
      expect(namespaces.uniq).to eq(namespaces)
      expect(namespaces).to eq([ns_class])
    end

    it "returns empty array when no rules" do
      transformation = test_transformation_class.new(
        model_class,
        mapping_dsl,
        format,
        register
      )

      namespaces = transformation.all_namespaces
      expect(namespaces).to eq([])
    end
  end

  describe "immutability" do
    it "prevents modification of model_class" do
      transformation = test_transformation_class.new(
        model_class,
        mapping_dsl,
        format,
        register
      )

      expect { transformation.instance_variable_set(:@model_class, nil) }
        .to raise_error(FrozenError)
    end

    it "prevents modification of compiled_rules" do
      transformation = test_transformation_class.new(
        model_class,
        mapping_dsl,
        format,
        register
      )

      expect { transformation.instance_variable_set(:@compiled_rules, []) }
        .to raise_error(FrozenError)
    end
  end
end