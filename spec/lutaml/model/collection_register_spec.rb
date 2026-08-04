require "spec_helper"
require_relative "../../../lib/lutaml/model"

module CollectionRegisterSpec
  # Inherits Collection#initialize, so it declares the register keyword.
  class Standard < Lutaml::Model::Collection
    instances :items, :string
  end

  # Overrides #initialize with the positional signature that predates the
  # register. Passing the keyword to this raises ArgumentError.
  class Positional < Lutaml::Model::Collection
    instances :items, :string

    def initialize(items = [])
      super
    end
  end

  # Accepts and forwards arbitrary keywords, so the register still arrives.
  class Forwarding < Lutaml::Model::Collection
    instances :items, :string

    def initialize(items = [], **)
      super
    end
  end

  class UsesStandard < Lutaml::Model::Serializable
    attribute :items, :string, collection: Standard
    key_value { map "items", to: :items }
  end

  class UsesPositional < Lutaml::Model::Serializable
    attribute :items, :string, collection: Positional
    key_value { map "items", to: :items }
  end

  class UsesForwarding < Lutaml::Model::Serializable
    attribute :items, :string, collection: Forwarding
    key_value { map "items", to: :items }
  end

  class UsesPlainArray < Lutaml::Model::Serializable
    attribute :items, :string, collection: true
    key_value { map "items", to: :items }
  end
end

RSpec.describe "collection construction and the register" do
  let(:register) { Lutaml::Model::Register.new(:collection_register_spec) }

  before { Lutaml::Model::GlobalRegister.register(register) }

  describe "a custom collection whose constructor takes the register" do
    it "receives the register used for the parse" do
      obj = CollectionRegisterSpec::UsesStandard.from_json(
        '{"items":["x","y"]}',
        register: :collection_register_spec,
      )

      expect(obj.items.lutaml_register).to eq(:collection_register_spec)
    end

    it "receives it through a forwarding constructor too" do
      obj = CollectionRegisterSpec::UsesForwarding.from_json(
        '{"items":["x","y"]}',
        register: :collection_register_spec,
      )

      expect(obj.items.lutaml_register).to eq(:collection_register_spec)
    end
  end

  describe "a custom collection with a positional-only constructor" do
    it "parses without raising ArgumentError" do
      obj = nil

      expect do
        obj = CollectionRegisterSpec::UsesPositional.from_json(
          '{"items":["x","y"]}',
        )
      end.not_to raise_error

      expect(obj.items.to_a).to eq(%w[x y])
    end

    it "accepts assignment without raising ArgumentError" do
      obj = CollectionRegisterSpec::UsesPositional.new

      expect { obj.items = %w[x y] }.not_to raise_error
      expect(obj.items.to_a).to eq(%w[x y])
    end

    # There is no way to hand a register to a constructor that does not take
    # one, so such a collection resolves against the default register.
    it "falls back to the default register under a non-default parse" do
      obj = CollectionRegisterSpec::UsesPositional.from_json(
        '{"items":["x"]}',
        register: :collection_register_spec,
      )

      expect(obj.items.lutaml_register)
        .to eq(Lutaml::Model::Config.default_register)
    end
  end

  describe "a plain collection: true attribute" do
    it "still builds a bare Array when a register is in play" do
      obj = CollectionRegisterSpec::UsesPlainArray.from_json(
        '{"items":["x","y"]}',
        register: :collection_register_spec,
      )

      expect(obj.items).to be_an(Array)
      expect(obj.items).to eq(%w[x y])
    end
  end
end
