# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Register-specific attribute methods" do
  let(:register) do
    Lutaml::Model::Register.new(:register_methods_test,
                                fallback: [:default])
  end

  let(:base_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      xml do
        element "Base"
        map_element "Name", to: :name
      end
    end
  end

  let(:extension_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :version, :string
      attribute :priority, :integer

      xml do
        element "Extension"
        map_element "Version", to: :version
        map_element "Priority", to: :priority
      end
    end
  end

  before do
    Lutaml::Model::GlobalContext.reset!
    Lutaml::Model::GlobalRegister.register(register)
    register.register_model(extension_model, id: :extension_model)
    base_model.import_model_attributes(extension_model, register.id)
  end

  describe "class-level method definition" do
    it "does not create singleton class methods for register-specific attributes" do
      instance = base_model.new({ name: "test",
                                  version: "1.0" },
                                register: register.id)

      expect(instance.version).to eq("1.0")

      # Method should be on the class, NOT directly on the singleton class
      expect(instance.singleton_class.instance_methods(false)).not_to include(:version)
      expect(instance.singleton_class.instance_methods(false)).not_to include(:version=)
    end

    it "defines methods on the class accessible to all instances" do
      instance1 = base_model.new({ name: "a" }, register: register.id)
      instance2 = base_model.new({ name: "b" }, register: register.id)

      instance1.version = "1.0"
      instance2.version = "2.0"

      expect(instance1.version).to eq("1.0")
      expect(instance2.version).to eq("2.0")
    end

    it "guards against re-definition with @_register_methods_defined" do
      base_model.new({ name: "a" }, register: register.id)

      guard = base_model.instance_variable_get(:@_register_methods_defined)
      expect(guard).to include(register.id => true)

      # Second instance creation should not re-trigger method definition
      base_model.new({ name: "b" }, register: register.id)
      expect(guard[register.id]).to be(true)
    end
  end

  describe "type casting in setter" do
    it "casts integer values correctly" do
      instance = base_model.new({ name: "test" }, register: register.id)

      instance.priority = "5"
      expect(instance.priority).to eq(5)
    end

    it "casts string values correctly" do
      instance = base_model.new({ name: "test" }, register: register.id)

      instance.version = 42
      expect(instance.version).to eq("42")
    end
  end

  describe "value_set_for tracking" do
    it "marks register-specific attributes as explicitly set" do
      instance = base_model.new({ name: "test" }, register: register.id)

      # After initialization, version was set via public_send in initialize_attributes
      expect(instance.using_default?(:version)).to be(false)
    end

    it "uses default when register-specific attribute is not provided" do
      instance = base_model.allocate_for_deserialization(register.id)

      # Not yet set — using default
      expect(instance.using_default?(:version)).to be(true)

      instance.version = "1.0"
      expect(instance.using_default?(:version)).to be(false)
    end
  end

  describe "default register instances" do
    it "returns early without defining methods for :default register" do
      base_model.ensure_register_methods_defined(:default)

      guard = base_model.instance_variable_get(:@_register_methods_defined)
      expect(guard).to be_nil
    end

    it "default-register instances still work for class-level attributes" do
      instance = base_model.new(name: "test")

      expect(instance.name).to eq("test")
      instance.name = "changed"
      expect(instance.name).to eq("changed")
    end
  end

  describe "deserialization path" do
    it "defines methods via finalize_deserialization" do
      instance = base_model.allocate_for_deserialization(register.id)
      instance.version = "3.0"

      expect(instance.version).to eq("3.0")
      expect(instance.singleton_class.instance_methods(false)).not_to include(:version)
    end
  end

  describe "clear_cache resets the guard" do
    it "clears @_register_methods_defined on clear_cache" do
      base_model.new({ name: "a" }, register: register.id)
      expect(base_model.instance_variable_get(:@_register_methods_defined)).not_to be_nil

      base_model.clear_cache
      expect(base_model.instance_variable_get(:@_register_methods_defined)).to be_nil
    end
  end
end
