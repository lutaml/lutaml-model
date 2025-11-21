# frozen_string_literal: true

require "spec_helper"
module RegisterSpec
  class CustomString < Lutaml::Model::Type::String; end
  class CustomInteger < Lutaml::Model::Type::Integer; end

  Lutaml::Model::Type.register(:custom_string, CustomString)

  class AddressFields < Lutaml::Model::Serializable
    attribute :location, :string
    attribute :postal_code, :custom_string
    attribute :active, :custom_string

    xml do
      no_root

      sequence do
        map_element :location, to: :location
        map_element :postalCode, to: :postal_code
      end
      map_element :active, to: :active
    end
  end

  class Address < Lutaml::Model::Serializable
    import_model_attributes AddressFields
  end

  class Names < Lutaml::Model::Serializable
    attribute :first_name, :custom_string
    choice(min: 1, max: 1) do
      attribute :middle_name, :custom_string
      attribute :last_name, :custom_string
    end

    xml do
      no_root

      map_element :firstName, to: :first_name
      map_element :middleName, to: :middle_name
      map_element :lastName, to: :last_name
    end
  end

  class User < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      import_model_attributes :address_fields
    end
    import_model :names
    restrict :active, values: ["yes", "no"]

    xml do
      root "user"

      import_model_mappings :address_fields
    end
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
      v1_register.register_model(RegisterSpec::CustomInteger,
                                 id: :custom_integer)
    end

    it "registers model with explicit id" do
      expect(v1_register.models[:custom_string]).to be_nil
    end

    it "allows overriding an existing type" do
      v1_register.register_model(Lutaml::Model::Type::String,
                                 id: :custom_string)
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

  describe "#resolve" do
    let(:v1_register) { described_class.new(:v1) }

    before do
      v1_register.register_model(RegisterSpec::Address, id: :address)
    end

    it "finds registered class by string representation" do
      expect(v1_register.resolve("RegisterSpec::Address")).to eq(RegisterSpec::Address)
    end

    it "returns nil for unregistered class" do
      expect(v1_register.resolve("UnknownClass")).to be_nil
    end
  end

  describe "#get_class" do
    let(:v1_register) { described_class.new(:v1) }

    before do
      v1_register.register_model(Lutaml::Model::Type::String, id: :custom_type)
    end

    it "returns registered class by key" do
      expect(v1_register.get_class(:custom_type)).to eq(Lutaml::Model::Type::String)
    end

    it "returns class by string using constant lookup" do
      expect(v1_register.get_class("String")).to eq(Lutaml::Model::Type::String)
    end

    it "returns class by symbol using Type.lookup" do
      allow(Lutaml::Model::Type).to receive(:lookup).with(:String).and_return(Lutaml::Model::Type::String)
      expect(v1_register.get_class(:String)).to eq(Lutaml::Model::Type::String)
    end

    it "returns class directly if class is provided" do
      expect(v1_register.get_class(Lutaml::Model::Type::String)).to eq(Lutaml::Model::Type::String)
    end

    it "raises error for unsupported type" do
      expect do
        v1_register.get_class(123)
      end.to raise_error(Lutaml::Model::UnknownTypeError)
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
      v1_register.register_global_type_substitution(from_type: :string,
                                                    to_type: :text)
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
      expect(v1_register.models.keys).not_to include(:string)
    end
  end

  describe "#import_model" do
    let(:register) { described_class.new(:import_model_test) }

    before do
      Lutaml::Model::GlobalRegister.register(register)
      register.register_model(RegisterSpec::AddressFields, id: :address_fields)
      register.register_model(RegisterSpec::Names, id: :names)
    end

    it "tracks imported model attributes by symbolic id in importable_choices" do
      expect(RegisterSpec::User.importable_choices.count).to eq(1)
    end

    it "tracks imported models attributes for 'restrict' functionality" do
      expect(RegisterSpec::User.restrict_attributes).to eq({ active: { values: ["yes", "no"] } })
    end

    it "preserves and accumulates attributes in main model when importing additional ones" do
      expect do
        RegisterSpec::User.ensure_imports!(register.id)
      end.to change {
        RegisterSpec::User.instance_variable_get(:@attributes).count
      }.from(0).to(6)
    end

    it "tracks changes made to attribute updated using 'restrict'" do
      expect(RegisterSpec::AddressFields.attributes[:active].options.keys).to be_empty
      expect(RegisterSpec::User.attributes[:active].options.keys).to eq(%i[choice values])
    end
  end
end
