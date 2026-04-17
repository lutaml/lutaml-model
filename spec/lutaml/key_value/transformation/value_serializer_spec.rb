# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::KeyValue::Transformation::ValueSerializer do
  let(:format) { :json }
  let(:register_id) { :default }
  let(:transformation_factory) do
    ->(_type_class) do
      double("Transformation",
             transform: double("Element",
                               to_hash: { "__root__" => { "name" => "test" } }))
    end
  end

  let(:serializer) do
    described_class.new(
      format: format,
      register_id: register_id,
      transformation_factory: transformation_factory,
    )
  end

  describe "#initialize" do
    it "stores format" do
      expect(serializer.format).to eq(:json)
    end

    it "stores register_id" do
      expect(serializer.register_id).to eq(:default)
    end

    it "stores transformation_factory" do
      expect(serializer.transformation_factory).to eq(transformation_factory)
    end
  end

  describe "#serialize_item" do
    context "with nil value" do
      it "returns nil" do
        rule = build_rule(attribute_type: String)
        expect(serializer.serialize_item(nil, rule)).to be_nil
      end
    end

    context "with uninitialized value" do
      it "returns nil" do
        rule = build_rule(attribute_type: String)
        expect(serializer.serialize_item(
                 Lutaml::Model::UninitializedClass.instance, rule
               )).to be_nil
      end
    end

    context "with primitive value using Type classes" do
      it "serializes string values via Type::String" do
        rule = build_rule(attribute_type: Lutaml::Model::Type::String)
        result = serializer.serialize_item("hello", rule)
        expect(result).to eq("hello")
      end

      it "serializes integer values via Type::Integer" do
        rule = build_rule(attribute_type: Lutaml::Model::Type::Integer)
        result = serializer.serialize_item(42, rule)
        expect(result).to eq(42)
      end

      it "serializes boolean true via Type::Boolean" do
        rule = build_rule(attribute_type: Lutaml::Model::Type::Boolean)
        result = serializer.serialize_item(true, rule)
        expect(result).to be true
      end

      it "serializes boolean false via Type::Boolean" do
        rule = build_rule(attribute_type: Lutaml::Model::Type::Boolean)
        result = serializer.serialize_item(false, rule)
        expect(result).to be false
      end
    end

    context "with primitive value using Ruby classes" do
      it "returns integer values as-is" do
        rule = build_rule(attribute_type: Integer)
        result = serializer.serialize_item(42, rule)
        expect(result).to eq(42)
      end
    end

    context "with nested model" do
      let(:nested_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          json do
            root "nested"
            map "name", to: :name
          end
        end
      end

      let(:rule) { build_rule(attribute_type: nested_class) }
      let(:nested_value) { nested_class.new(name: "test") }

      it "uses transformation factory for nested models" do
        result = serializer.serialize_item(nested_value, rule)
        expect(result).to eq({ "name" => "test" })
      end

      it "validates type mismatch" do
        wrong_value = double("wrong_type")
        expect do
          serializer.serialize_item(wrong_value, rule)
        end.to raise_error(Lutaml::Model::IncorrectModelError, /but should be/)
      end
    end
  end

  describe "#nested_model?" do
    it "returns true for Serializable types" do
      serializable_class = Class.new(Lutaml::Model::Serializable)
      rule = build_rule(attribute_type: serializable_class)
      expect(serializer.nested_model?(rule)).to be true
    end

    it "returns false for primitive types" do
      rule = build_rule(attribute_type: String)
      expect(serializer.nested_model?(rule)).to be false
    end

    it "returns false for Integer type" do
      rule = build_rule(attribute_type: Integer)
      expect(serializer.nested_model?(rule)).to be false
    end

    it "returns false for Type::String" do
      rule = build_rule(attribute_type: Lutaml::Model::Type::String)
      expect(serializer.nested_model?(rule)).to be false
    end
  end

  describe "#serialize_primitive" do
    context "with Type classes" do
      it "serializes string values via Type::String" do
        rule = build_rule(attribute_type: Lutaml::Model::Type::String)
        result = serializer.serialize_primitive("hello", rule)
        expect(result).to eq("hello")
      end

      it "serializes integer values via Type::Integer" do
        rule = build_rule(attribute_type: Lutaml::Model::Type::Integer)
        result = serializer.serialize_primitive(42, rule)
        expect(result).to eq(42)
      end

      it "serializes date values via Type::Date" do
        rule = build_rule(attribute_type: Lutaml::Model::Type::Date)
        date = Date.new(2024, 1, 15)
        result = serializer.serialize_primitive(date, rule)
        # Type::Date returns ISO8601 string via registered JSON serializer
        expect(result).to eq("2024-01-15")
      end

      it "serializes date values via Type::Date for yaml format" do
        yaml_serializer = described_class.new(
          format: :yaml,
          register_id: register_id,
          transformation_factory: transformation_factory,
        )
        rule = build_rule(attribute_type: Lutaml::Model::Type::Date)
        date = Date.new(2024, 1, 15)
        result = yaml_serializer.serialize_primitive(date, rule)
        # Type::Date returns ISO8601 string for yaml
        expect(result).to eq("2024-01-15")
      end
    end

    context "with Ruby classes" do
      it "returns integer values as-is" do
        rule = build_rule(attribute_type: Integer)
        result = serializer.serialize_primitive(42, rule)
        expect(result).to eq(42)
      end
    end

    it "returns nil for nil values" do
      rule = build_rule(attribute_type: String)
      expect(serializer.serialize_primitive(nil, rule)).to be_nil
    end

    it "returns nil for uninitialized values" do
      rule = build_rule(attribute_type: String)
      expect(serializer.serialize_primitive(
               Lutaml::Model::UninitializedClass.instance, rule
             )).to be_nil
    end
  end

  describe "RenderPolicy integration" do
    it "includes RenderPolicy module" do
      expect(serializer).to respond_to(:should_skip_value?)
    end

    it "includes should_skip_value? method" do
      expect(serializer).to respond_to(:should_skip_value?)
    end
  end

  # Helper method to build a mock rule
  def build_rule(attribute_type:, attribute_name: :test,
child_transformation: nil)
    double("CompiledRule",
           attribute_type: attribute_type,
           attribute_name: attribute_name,
           child_transformation: child_transformation,
           collection?: false)
  end
end
