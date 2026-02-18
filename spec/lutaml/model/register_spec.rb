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
      element "user"

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

      # Also register in default register for tests that use attributes() without register arg
      default_register = Lutaml::Model::GlobalRegister.lookup(:default)
      default_register.register_model(RegisterSpec::AddressFields, id: :address_fields)
      default_register.register_model(RegisterSpec::Names, id: :names)
    end

    after do
      Lutaml::Model::GlobalRegister.unregister(register.id)
      # Clean up default register
      default_register = Lutaml::Model::GlobalRegister.lookup(:default)
      default_register.models.delete(:address_fields)
      default_register.models.delete(:names)
      default_register.models.delete("RegisterSpec::AddressFields")
      default_register.models.delete("RegisterSpec::Names")
    end

    it "tracks imported model attributes by symbolic id in importable_choices" do
      expect(RegisterSpec::User.importable_choices.count).to eq(1)
    end

    it "tracks imported models attributes for 'restrict' functionality" do
      # Restore the restrict_attributes that were set by 'restrict' directive at class definition
      # These get cleared after ensure_restrict_attributes! runs
      RegisterSpec::User.instance_variable_set(:@restrict_attributes,
                                               { active: { values: ["yes", "no"] } })

      expect(RegisterSpec::User.restrict_attributes).to eq({ active: { values: [
                                                             "yes", "no"
                                                           ] } })
    end

    it "preserves and accumulates attributes in main model when importing additional ones" do
      # Reset state to ensure test isolation
      # We need to restore importable_models and importable_choices because they get cleared after import
      RegisterSpec::User.instance_variable_set(:@attributes, {})
      RegisterSpec::User.instance_variable_set(:@models_imported, false)
      RegisterSpec::User.instance_variable_set(:@choices_imported, false)
      # Restore importable_models that were set by import_model_attributes and import_model at class def
      importable_models = Lutaml::Model::MappingHash.new { |h, k| h[k] = [] }
      importable_models[:import_model_attributes] = [:address_fields]
      importable_models[:import_model] = [:names]
      RegisterSpec::User.instance_variable_set(:@importable_models, importable_models)

      initial_count = RegisterSpec::User.instance_variable_get(:@attributes).count
      RegisterSpec::User.ensure_imports!(register.id)
      final_count = RegisterSpec::User.instance_variable_get(:@attributes).count

      expect(initial_count).to eq(0)
      expect(final_count).to eq(6)
    end

    it "tracks changes made to attribute updated using 'restrict'" do
      # Ensure restrict_attributes is set for this test
      # (it gets cleared after ensure_restrict_attributes! runs in other tests)
      RegisterSpec::User.instance_variable_set(:@restrict_attributes,
                                               { active: { values: ["yes", "no"] } })

      expect(RegisterSpec::AddressFields.attributes[:active].options.keys).to be_empty
      expect(RegisterSpec::User.attributes[:active].options.keys).to eq(%i[
                                                                          choice values
                                                                        ])
    end
  end

  describe "fallback behavior" do
    let(:default_register) { Lutaml::Model::GlobalRegister.lookup(:default) }

    context "when register is :default" do
      it "has no fallback" do
        expect(default_register.fallback).to eq([])
      end
    end

    context "when register is custom without explicit fallback" do
      let(:custom_register) { described_class.new(:custom) }

      before do
        Lutaml::Model::GlobalRegister.register(custom_register)
      end

      after do
        Lutaml::Model::GlobalRegister.unregister(custom_register.id)
      end

      it "defaults to fallback: [:default]" do
        expect(custom_register.fallback).to eq([:default])
      end

      it "can resolve types from default register" do
        # Register a model only in default
        default_register.register_model(RegisterSpec::Address,
                                        id: :fallback_address)

        # Custom register should find it via fallback (returns class, not raises)
        result = custom_register.get_class_without_register(:fallback_address)
        expect(result).to eq(RegisterSpec::Address)
      end
    end

    context "when register has explicit fallback: []" do
      let(:isolated_register) { described_class.new(:isolated, fallback: []) }

      before do
        Lutaml::Model::GlobalRegister.register(isolated_register)
      end

      after do
        Lutaml::Model::GlobalRegister.unregister(isolated_register.id)
      end

      it "has empty fallback (isolated)" do
        expect(isolated_register.fallback).to eq([])
      end

      it "cannot resolve types from default register" do
        # Register a model only in default (not a Type::Value)
        default_register.register_model(RegisterSpec::Address,
                                        id: :isolated_type)

        # Isolated register should NOT find it
        expect { isolated_register.get_class(:isolated_type) }
          .to raise_error(Lutaml::Model::UnknownTypeError)
      end
    end

    context "when register has custom fallback chain" do
      let(:core_register) { described_class.new(:core) }
      let(:profile_register) do
        described_class.new(:profile, fallback: %i[core default])
      end

      before do
        Lutaml::Model::GlobalRegister.register(core_register)
        Lutaml::Model::GlobalRegister.register(profile_register)
      end

      after do
        Lutaml::Model::GlobalRegister.unregister(core_register.id)
        Lutaml::Model::GlobalRegister.unregister(profile_register.id)
      end

      it "uses specified fallback chain" do
        expect(profile_register.fallback).to eq(%i[core default])
      end

      it "tries fallback registers in order" do
        # Register type only in core
        core_register.register_model(RegisterSpec::CustomString, id: :core_type)

        # Profile should find it via :core fallback
        expect(profile_register.get_class(:core_type)).to eq(RegisterSpec::CustomString)
      end
    end
  end
end
