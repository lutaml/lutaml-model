# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/registry"

class Address < Lutaml::Model::Serializable
  attribute :location, :string
end

RSpec.describe Lutaml::Model::Registry do
  let(:register_address_class) do
    Lutaml::Model::Registry.register(:address, Address)
  end

  describe ".register" do
    before { described_class.register(:custom_string, String) }

    it "registers a new type" do
      expect(described_class.registry).to include(custom_string: String)
    end

    it "overrides an existing type" do
      described_class.register(:custom_string, Integer)
      expect(described_class.registry).to include(custom_string: Integer)
    end

    it "registers serializable class" do
      register_address_class
      expect(described_class.registry).to include(address: Address)
    end
  end

  describe ".lookup!" do
    context "when the type is registered" do
      before do
        described_class.register(:registered_type, Array)
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
      before { register_address_class }

      it "returns the new registered class" do
        OtherAddress = Class.new(Lutaml::Model::Serializable)
        described_class.register(:address, OtherAddress)
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
end
