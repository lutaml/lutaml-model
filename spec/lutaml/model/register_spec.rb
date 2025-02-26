# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/register"

class Address < Lutaml::Model::Serializable
  attribute :location, :string
end

RSpec.describe Lutaml::Model::Register do
  let(:register_address_class) do
    described_class.register_model(:address, Address)
  end

  describe ".register_model" do
    before { described_class.register_model(:custom_string, String) }

    it "registers a new type" do
      expect(described_class.register).to include(custom_string: String)
    end

    it "overrides an existing type" do
      described_class.register_model(:custom_string, Integer)
      expect(described_class.register).to include(custom_string: Integer)
    end

    it "registers serializable class" do
      register_address_class
      expect(described_class.register).to include(address: Address)
    end
  end

  describe ".lookup!" do
    context "when the type is registered" do
      before do
        described_class.register_model(:registered_type, Array)
      end

      it "returns the registered type" do
        expect(described_class.lookup!(:registered_type)).to eq(Array)
      end
    end

    context "when the serializable class is registered" do
      before { register_address_class }

      it "returns the registered class" do
        expect(described_class.lookup!(:address)).to eq(Address)
      end
    end

    context "when the serializable class is overriden registered" do
      before do
        register_address_class
        stub_const(
          "OtherAddress",
          Class.new(Lutaml::Model::Serializable),
        )
      end

      it "returns the new registered class" do
        described_class.register_model(:address, OtherAddress)
        expect(described_class.lookup!(:address)).to eq(OtherAddress)
      end
    end

    context "when the type is not registered" do
      it "raises an UnknownTypeError" do
        expect do
          described_class.lookup!(:unknown_type)
        end.to raise_error(
          Lutaml::Model::UnknownTypeError,
          "Unknown type 'unknown_type'",
        )
      end
    end

    context "when the type is not of supported data type" do
      it "raises an UnknownTypeError" do
        expect do
          described_class.lookup!({})
        end.to raise_error(
          Lutaml::Model::UnknownTypeError,
          "Unknown type '{}'",
        )
      end
    end
  end

  describe ".register_model_tree" do
    context "when registering a valid model" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :nested_address, Address
        end
      end

      it "registers the model and its nested attributes" do
        described_class.register_model_tree(model_class)
        expect(described_class.lookup?(model_class)).to be true
        expect(described_class.lookup?(Address)).to be true
      end
    end

    context "when model is not a Serializable class" do
      it "raises InvalidModelClassError" do
        expect do
          described_class.register_model_tree(String)
        end.to raise_error(Lutaml::Model::InvalidModelClassError)
      end
    end

    context "when model is already registered" do
      let(:model_class) { Class.new(Lutaml::Model::Serializable) }

      before { described_class.register_model_tree(model_class) }

      it "raises UnexpectedModelReplacementError" do
        expect do
          described_class.register_model_tree(model_class)
        end.to raise_error(Lutaml::Model::UnexpectedModelReplacementError)
      end
    end
  end

  describe ".register_global_type_substitution" do
    it "registers a global type substitution" do
      described_class.register_global_type_substitution(from_type: :string, to_type: :text)
      expect(described_class.instance_variable_get(:@global_substitutions)).to include(string: :text)
    end
  end

  describe ".resolve" do
    before { described_class.register_model(:custom_type, String) }

    it "finds registered class by string representation" do
      expect(described_class.resolve("String")).to eq(String)
    end

    it "returns nil for unregistered class" do
      expect(described_class.resolve("UnknownClass")).to be_nil
    end
  end

  describe ".get_class" do
    before { described_class.register_model(:custom_type, String) }

    it "returns registered class by key" do
      expect(described_class.get_class(:custom_type)).to eq(String)
    end

    it "returns nil for unregistered key" do
      expect(described_class.get_class(:unknown_key)).to be_nil
    end
  end
end
