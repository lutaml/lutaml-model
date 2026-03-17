# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::KeyValue::Transformation::RuleCompiler do
  let(:format) { :json }
  let(:register_id) { :default }

  # Create a simple model class for testing with only primitive types
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer
      attribute :active, :boolean

      json do
        root "person"
        map "name", to: :name
        map "age", to: :age
        map "active", to: :active
      end

      def self.name
        "Person"
      end
    end
  end

  let(:transformation_factory) do
    ->(_type_class) { double("Transformation") }
  end

  let(:compiler) do
    described_class.new(
      model_class: model_class,
      register_id: register_id,
      format: format,
      transformation_factory: transformation_factory,
    )
  end

  before do
    # Reset global state
    Lutaml::Model::GlobalContext.clear_caches
  end

  describe "#initialize" do
    it "stores model_class" do
      expect(compiler.model_class).to eq(model_class)
    end

    it "stores register_id" do
      expect(compiler.register_id).to eq(:default)
    end

    it "stores format" do
      expect(compiler.format).to eq(:json)
    end

    it "stores transformation_factory" do
      expect(compiler.transformation_factory).to eq(transformation_factory)
    end
  end

  describe "#compile" do
    context "with nil mapping_dsl" do
      it "returns empty array" do
        expect(compiler.compile(nil)).to eq([])
      end
    end

    context "with valid mapping" do
      let(:mapping_dsl) { model_class.mappings_for(:json) }

      it "returns array of compiled rules" do
        rules = compiler.compile(mapping_dsl)
        expect(rules).to be_an(Array)
        expect(rules.length).to eq(3) # name, age, active
      end

      it "compiles each mapping rule" do
        rules = compiler.compile(mapping_dsl)
        attribute_names = rules.map(&:attribute_name)
        expect(attribute_names).to contain_exactly(:name, :age, :active)
      end

      it "creates CompiledRule instances" do
        rules = compiler.compile(mapping_dsl)
        expect(rules).to all(be_a(Lutaml::Model::CompiledRule))
      end
    end
  end

  describe "#compile_rule" do
    let(:mapping_dsl) { model_class.mappings_for(:json) }
    let(:mapping_rule) { mapping_dsl.mappings.first }

    it "compiles a mapping rule to CompiledRule" do
      rule = compiler.compile_rule(mapping_rule, mapping_dsl)
      expect(rule).to be_a(Lutaml::Model::CompiledRule)
    end

    it "sets attribute_name from rule's to attribute" do
      rule = compiler.compile_rule(mapping_rule, mapping_dsl)
      expect(rule.attribute_name).to eq(:name)
    end

    it "sets serialized_name from rule's name" do
      rule = compiler.compile_rule(mapping_rule, mapping_dsl)
      expect(rule.serialized_name).to eq("name")
    end

    it "sets attribute_type from model's attribute" do
      rule = compiler.compile_rule(mapping_rule, mapping_dsl)
      expect(rule.attribute_type).to eq(Lutaml::Model::Type::String)
    end

    it "sets render_nil from rule's render_nil" do
      rule = compiler.compile_rule(mapping_rule, mapping_dsl)
      expect(rule.render_nil).to eq(mapping_rule.render_nil)
    end

    context "with custom methods but no 'to' attribute" do
      let(:custom_mapping_rule) do
        rule = Lutaml::KeyValue::MappingRule.new("custom_key", to: nil)
        rule.instance_variable_set(:@custom_methods, { to: :custom_method })
        rule.instance_variable_set(:@name, "custom_key")
        rule
      end

      it "uses serialized name as placeholder attribute name" do
        rule = compiler.compile_rule(custom_mapping_rule, mapping_dsl)
        expect(rule.attribute_name).to eq(:custom_key)
      end
    end
  end

  describe "#valid_mapping?" do
    let(:rule) { double("CompiledRule", attribute_name: :name) }

    it "returns true when no only/except options" do
      expect(compiler.valid_mapping?(rule, {})).to be true
    end

    it "returns true when attribute is in only list" do
      expect(compiler.valid_mapping?(rule, { only: [:name] })).to be true
    end

    it "returns false when attribute is not in only list" do
      expect(compiler.valid_mapping?(rule, { only: [:age] })).to be false
    end

    it "returns true when attribute is not in except list" do
      expect(compiler.valid_mapping?(rule, { except: [:age] })).to be true
    end

    it "returns false when attribute is in except list" do
      expect(compiler.valid_mapping?(rule, { except: [:name] })).to be false
    end
  end

  describe "#build_child_transformation" do
    context "with valid Serializable class" do
      let(:nested_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string
        end
      end

      it "calls transformation factory" do
        expect(transformation_factory).to receive(:call).with(nested_class)
        compiler.send(:build_child_transformation, nested_class)
      end
    end

    context "with non-Serializable class" do
      it "returns nil for non-Serializable classes" do
        result = compiler.send(:build_child_transformation, String)
        expect(result).to be_nil
      end
    end

    context "with non-class object" do
      it "returns nil for non-class objects" do
        result = compiler.send(:build_child_transformation, "not a class")
        expect(result).to be_nil
      end
    end
  end

  describe "#build_value_transformer" do
    let(:attr) { model_class.attributes[:name] }
    let(:mapping_rule) { mapping_dsl.mappings.first }
    let(:mapping_dsl) { model_class.mappings_for(:json) }

    it "returns nil when no transform defined" do
      result = compiler.send(:build_value_transformer, mapping_rule, attr)
      expect(result).to be_nil
    end

    context "with mapping-level transform" do
      let(:transform_hash) { { export: lambda(&:upcase) } }
      let(:mapping_rule) do
        rule = super()
        allow(rule).to receive(:transform).and_return(transform_hash)
        allow(rule).to receive(:respond_to?).with(:transform).and_return(true)
        rule
      end

      it "returns mapping transform when present" do
        result = compiler.send(:build_value_transformer, mapping_rule, attr)
        expect(result).to eq(transform_hash)
      end
    end

    context "with attribute-level transform" do
      let(:transform_hash) { { export: lambda(&:upcase) } }
      let(:attr) do
        double("Attribute", options: { transform: transform_hash },
                            respond_to?: false)
      end

      it "returns attribute transform when present" do
        result = compiler.send(:build_value_transformer, mapping_rule, attr)
        expect(result).to eq(transform_hash)
      end
    end
  end
end
