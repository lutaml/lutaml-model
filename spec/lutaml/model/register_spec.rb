# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/error/register/invalid_model_class_error"
require "lutaml/model/register"

module RegisterSpec
  class CustomString < Lutaml::Model::Type::String; end
  class CustomInteger < Lutaml::Model::Type::Integer; end

  Lutaml::Model::Type.register(:custom_string, CustomString)

  class Address < Lutaml::Model::Serializable
    attribute :location, :string
    attribute :postal_code, :custom_string
  end
end

RSpec.describe Lutaml::Model::Register do
  describe "#initialize" do
    it "initializes with id" do
      register = described_class.new(:v1)
      expect(register.id).to eq(:v1)
      expect(register.models).to eq({})
    end
  end

  describe "#register_model" do
    let(:v1_register) { described_class.new(:v1) }

    before do
      v1_register.register_model(RegisterSpec::CustomString, id: :custom_string)
      v1_register.register_model(RegisterSpec::CustomInteger, id: :custom_integer)
    end

    it "registers model with explicit id" do
      expect(v1_register.models[:custom_string]).to be_nil
    end

    it "allows overriding an existing type" do
      v1_register.register_model(Lutaml::Model::Type::String, id: :custom_string)
      expect(v1_register.models[:custom_string]).to be_nil
    end

    it "registers serializable class" do
      v1_register.register_model(RegisterSpec::Address, id: :address)
      expect(v1_register.models[:address]).to eq(RegisterSpec::Address)
    end

    it "registers model without explicit id" do
      stub_const("TestModel", Class.new(Lutaml::Model::Serializable))
      v1_register.register_model(TestModel)
      expect(v1_register.models[:test_model]).to eq(TestModel)
    end
  end

  describe "#lookup" do
    let(:v1_register) { described_class.new(:v1) }

    before do
      v1_register.register_model(Array, id: :registered_type)
    end

    it "returns registered model by symbol key" do
      expect(v1_register.lookup(:registered_type)).to eq(Array)
    end

    it "returns registered model by class" do
      v1_register.register_model(String)
      expect(v1_register.lookup(String)).to eq(String)
    end

    it "returns nil for unregistered class" do
      expect(v1_register.lookup(Hash)).to be_nil
    end
  end

  describe "#resolve" do
    let(:v1_register) { described_class.new(:v1) }

    before do
      v1_register.register_model(String, id: :custom_type)
    end

    it "finds registered class by string representation" do
      expect(v1_register.resolve("String")).to eq(String)
    end

    it "returns nil for unregistered class" do
      expect(v1_register.resolve("UnknownClass")).to be_nil
    end
  end

  describe "#get_class" do
    let(:v1_register) { described_class.new(:v1) }

    before do
      v1_register.register_model(String, id: :custom_type)
    end

    it "returns registered class by key" do
      expect(v1_register.get_class(:custom_type)).to eq(String)
    end

    it "returns class by string using constant lookup" do
      expect(v1_register.get_class("String")).to eq(String)
    end

    it "returns class by symbol using Type.lookup" do
      allow(Lutaml::Model::Type).to receive(:lookup).with(:String).and_return(String)
      expect(v1_register.get_class(:String)).to eq(String)
    end

    it "returns class directly if class is provided" do
      expect(v1_register.get_class(String)).to eq(String)
    end

    it "raises error for unsupported type" do
      expect { v1_register.get_class(123) }.to raise_error(Lutaml::Model::UnknownTypeError)
    end
  end

  describe "#register_model_tree" do
    let(:v1_register) { described_class.new(:v1) }

    context "when registering a valid model" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :nested_address, RegisterSpec::Address
        end
      end

      it "registers the model and its nested attributes" do
        v1_register.register_model_tree(model_class)
        expect(v1_register.models.values).to include(model_class)
        expect(v1_register.models.values).to include(RegisterSpec::Address)
      end
    end
  end

  describe "#register_global_type_substitution" do
    let(:v1_register) { described_class.new(:v1) }

    it "registers a global type substitution" do
      v1_register.register_global_type_substitution(from_type: :string, to_type: :text)
      expect(v1_register.instance_variable_get(:@global_substitutions)).to include(string: :text)
    end
  end

  describe "#register_attributes" do
    let(:v1_register) { described_class.new(:v1) }
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :nested_address, RegisterSpec::Address
        attribute :string_attr, :string
      end
    end

    it "registers non-builtin type attributes" do
      attributes = model_class.attributes
      v1_register.register_attributes(attributes)
      expect(v1_register.models.values).to include(RegisterSpec::Address)
    end

    it "doesn't register built-in types" do
      attributes = model_class.attributes
      v1_register.register_attributes(attributes)
      # Verify built-in type (:string) wasn't registered
      expect(v1_register.models.keys).not_to include(:string)
    end

    it "uses register_model_tree! when strict is true" do
      attributes = model_class.attributes
      allow(v1_register).to receive(:register_model_tree!)
      v1_register.register_attributes(attributes, strict: true)
      expect(v1_register).to have_received(:register_model_tree!).with(RegisterSpec::Address)
    end
  end

  describe "#register_model!" do
    let(:v1_register) { described_class.new(:v1) }

    it "raises InvalidModelClassError when model is not a Serializable class" do
      expect do
        v1_register.register_model!(String)
      end.to raise_error(Lutaml::Model::Register::InvalidModelClassError)
    end

    it "raises UnexpectedModelReplacementError when model is already registered" do
      stub_const("ModelClass", Class.new(Lutaml::Model::Serializable))
      v1_register.register_model(ModelClass, id: ModelClass.name.to_sym)

      expect do
        v1_register.register_model!(ModelClass)
      end.to raise_error(Lutaml::Model::Register::UnexpectedModelReplacementError)
    end

    it "registers serializable class when valid" do
      v1_register.register_model!(RegisterSpec::Address, id: :address)
      expect(v1_register.lookup(:address)).to eq(RegisterSpec::Address)
    end
  end

  describe "#register_model_tree!" do
    let(:v1_register) { described_class.new(:v1) }

    context "when registering a valid model" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :nested_address, RegisterSpec::Address
        end
      end

      it "registers the model and its nested attributes" do
        v1_register.register_model_tree!(model_class)
        expect(v1_register.models.values).to include(model_class)
        expect(v1_register.models.values).to include(RegisterSpec::Address)
        expect { v1_register.register_model_tree!(model_class) }.to raise_error(Lutaml::Model::Register::UnexpectedModelReplacementError)
      end
    end
  end
end
