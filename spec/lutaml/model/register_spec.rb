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

  # Test classes for register-specific attribute casting
  class BaseModel < Lutaml::Model::Serializable
    attribute :base_field, :string
  end

  class ExtendedModel < Lutaml::Model::Serializable
    attribute :extended_field, :integer
    import_model BaseModel
  end

  class DynamicImporter < Lutaml::Model::Serializable
    import_model :dynamic_model
  end

  # Test classes for choice with register-specific imports
  class ChoiceFieldsA < Lutaml::Model::Serializable
    attribute :field_a, :string
    attribute :field_b, :integer
  end

  class ChoiceFieldsB < Lutaml::Model::Serializable
    attribute :field_x, :string
    attribute :field_y, :boolean
  end

  class DynamicChoiceModel < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      import_model_attributes :choice_fields
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

    it "preserves and accumulates attributes in register-specific storage when importing" do
      RegisterSpec::User.ensure_imports!(register.id)
      expect(RegisterSpec::User.instance_variable_get(:@attributes).count).to eq(0)
      expect(RegisterSpec::User.attributes(register.id).count).to eq(6)
    end

    it "tracks changes made to attribute updated using 'restrict'" do
      expect(RegisterSpec::AddressFields.attributes(register.id)[:active].options.keys).to be_empty
      expect(RegisterSpec::User.attributes(register.id)[:active].options.keys).to eq(%i[choice values])
    end
  end

  describe "register-specific attribute casting and method availability" do
    let(:extended_register) { described_class.new(:casting_test_r1) }
    let(:base_register) { described_class.new(:casting_test_r2) }

    before do
      Lutaml::Model::GlobalRegister.register(extended_register)
      Lutaml::Model::GlobalRegister.register(base_register)
      extended_register.register_model(RegisterSpec::ExtendedModel, id: :dynamic_model)
      base_register.register_model(RegisterSpec::BaseModel, id: :dynamic_model)
    end

    it "imports different attributes based on register mapping" do
      RegisterSpec::DynamicImporter.ensure_imports!(extended_register.id)
      RegisterSpec::DynamicImporter.ensure_imports!(base_register.id)

      expect(RegisterSpec::DynamicImporter.attributes(extended_register.id).keys).to include(:extended_field, :base_field)
      expect(RegisterSpec::DynamicImporter.attributes(base_register.id).keys).to eq([:base_field])
    end

    it "provides attribute accessor methods based on register-specific imports" do
      extended_instance = RegisterSpec::DynamicImporter.new(__register: extended_register)
      base_instance = RegisterSpec::DynamicImporter.new(__register: base_register)

      expect(extended_instance).to respond_to(:extended_field)
      expect(extended_instance).to respond_to(:extended_field=)
      expect(extended_instance).to respond_to(:base_field)
      expect(extended_instance).to respond_to(:base_field=)

      expect(base_instance).to respond_to(:base_field)
      expect(base_instance).to respond_to(:base_field=)
      expect(base_instance).not_to respond_to(:extended_field)
      expect(base_instance).not_to respond_to(:extended_field=)
    end

    it "casts attribute values correctly based on register-specific type definitions" do
      extended_instance = RegisterSpec::DynamicImporter.new(__register: extended_register)
      base_instance = RegisterSpec::DynamicImporter.new(__register: base_register)

      extended_instance.extended_field = "42"
      expect(extended_instance.extended_field).to eq(42)
      expect(extended_instance.extended_field).to be_a(Integer)

      extended_instance.base_field = "test"
      expect(extended_instance.base_field).to eq("test")
      expect(extended_instance.base_field).to be_a(String)

      base_instance.base_field = "test"
      expect(base_instance.base_field).to eq("test")
      expect(base_instance.base_field).to be_a(String)
    end

    it "raises NoMethodError for attributes not in the register" do
      base_instance = RegisterSpec::DynamicImporter.new(__register: base_register)

      expect { base_instance.extended_field }.to raise_error(NoMethodError)
      expect { base_instance.extended_field = 42 }.to raise_error(NoMethodError)
    end
  end

  describe "register-specific choice imports" do
    let(:fields_a_register) { described_class.new(:choice_test_a) }
    let(:fields_b_register) { described_class.new(:choice_test_b) }

    before do
      Lutaml::Model::GlobalRegister.register(fields_a_register)
      Lutaml::Model::GlobalRegister.register(fields_b_register)
      fields_a_register.register_model(RegisterSpec::ChoiceFieldsA, id: :choice_fields)
      fields_b_register.register_model(RegisterSpec::ChoiceFieldsB, id: :choice_fields)
    end

    it "imports different choice attributes based on register" do
      RegisterSpec::DynamicChoiceModel.ensure_imports!(fields_a_register.id)
      RegisterSpec::DynamicChoiceModel.ensure_imports!(fields_b_register.id)

      expect(RegisterSpec::DynamicChoiceModel.attributes(fields_a_register.id).keys).to match_array(%i[field_a field_b])
      expect(RegisterSpec::DynamicChoiceModel.attributes(fields_b_register.id).keys).to match_array(%i[field_x field_y])
    end

    it "sets choice option on imported attributes" do
      RegisterSpec::DynamicChoiceModel.ensure_imports!(fields_a_register.id)

      field_a = RegisterSpec::DynamicChoiceModel.attributes(fields_a_register.id)[:field_a]
      field_b = RegisterSpec::DynamicChoiceModel.attributes(fields_a_register.id)[:field_b]

      expect(field_a.options[:choice]).to be_a(Lutaml::Model::Choice)
      expect(field_b.options[:choice]).to be_a(Lutaml::Model::Choice)
    end

    it "provides correct accessor methods for choice attributes by register" do
      fields_a_instance = RegisterSpec::DynamicChoiceModel.new(__register: fields_a_register)
      fields_b_instance = RegisterSpec::DynamicChoiceModel.new(__register: fields_b_register)

      expect(fields_a_instance).to respond_to(:field_a)
      expect(fields_a_instance).to respond_to(:field_b)
      expect(fields_a_instance).not_to respond_to(:field_x)
      expect(fields_a_instance).not_to respond_to(:field_y)

      expect(fields_b_instance).to respond_to(:field_x)
      expect(fields_b_instance).to respond_to(:field_y)
      expect(fields_b_instance).not_to respond_to(:field_a)
      expect(fields_b_instance).not_to respond_to(:field_b)
    end

    it "casts choice attribute values correctly by register-specific types" do
      fields_a_instance = RegisterSpec::DynamicChoiceModel.new(__register: fields_a_register)

      fields_a_instance.field_a = "test_value"
      fields_a_instance.field_b = "123"

      expect(fields_a_instance.field_a).to eq("test_value")
      expect(fields_a_instance.field_a).to be_a(String)
      expect(fields_a_instance.field_b).to eq(123)
      expect(fields_a_instance.field_b).to be_a(Integer)
    end
  end
end
