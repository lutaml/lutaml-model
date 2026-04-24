# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::GlobalRegister do
  # GlobalRegister is now a pure facade that delegates to GlobalContext
  # Tests verify the public API behavior, not internal implementation

  describe "#initialize" do
    it "initializes with a default context" do
      expect(described_class.lookup(:default)).not_to be_nil
    end
  end

  describe "#register" do
    after do
      described_class.remove(:test_register) if described_class.lookup(:test_register)
    end

    it "returns the register for backward compatibility" do
      register = Lutaml::Model::Register.new(:test_register)
      result = described_class.register(register)
      expect(result).to eq(register)
    end

    it "makes the register available via lookup" do
      register = Lutaml::Model::Register.new(:test_register)
      described_class.register(register)
      expect(described_class.lookup(:test_register)).not_to be_nil
    end
  end

  describe ".register" do
    after do
      described_class.remove(:temp_register) if described_class.lookup(:temp_register)
    end

    it "makes register available via lookup" do
      register = Lutaml::Model::Register.new(:temp_register)
      described_class.register(register)
      expect(described_class.lookup(:temp_register)).not_to be_nil
    end
  end

  describe "#lookup" do
    let(:register_v_one) { Lutaml::Model::Register.new(:v1_lookup_test) }
    let(:register_v_two) { Lutaml::Model::Register.new(:v2_lookup_test) }

    before do
      described_class.instance.register(register_v_one)
      described_class.instance.register(register_v_two)
    end

    after do
      described_class.remove(:v1_lookup_test)
      described_class.remove(:v2_lookup_test)
    end

    it "returns a register for a given id" do
      expect(described_class.instance.lookup(:v1_lookup_test)).not_to be_nil
      expect(described_class.instance.lookup(:v2_lookup_test)).not_to be_nil
    end

    it "returns nil for non-existent id" do
      expect(described_class.instance.lookup(:non_existent)).to be_nil
    end

    it "converts string id to symbol" do
      expect(described_class.instance.lookup("v1_lookup_test")).not_to be_nil
    end

    context "when context exists in GlobalContext but no Register was registered" do
      let(:context_id) { :context_only_test }

      before do
        Lutaml::Model::GlobalContext.create_context(
          id: context_id,
          fallback_to: [:default],
        )
      end

      after do
        described_class.remove(context_id) if described_class.lookup(context_id)
        Lutaml::Model::GlobalContext.unregister_context(context_id)
      end

      it "creates a Register from the context and returns it" do
        result = described_class.lookup(context_id)
        expect(result).to be_a(Lutaml::Model::Register)
        expect(result.id).to eq(context_id)
      end

      it "caches the created Register for subsequent lookups" do
        first_result = described_class.lookup(context_id)
        second_result = described_class.lookup(context_id)
        expect(first_result).to be(second_result)
      end

      it "resolves types registered in the context through the created Register" do
        custom_class = Class.new(Lutaml::Model::Type::Value)
        ctx = Lutaml::Model::GlobalContext.context(context_id)
        ctx.registry.register(:custom_type, custom_class)

        described_class.lookup(context_id)
        resolved = Lutaml::Model::GlobalContext.resolve_type(:custom_type,
                                                             context_id)
        expect(resolved).to eq(custom_class)
      end

      it "resolves built-in types via fallback to default context" do
        register = described_class.lookup(context_id)
        result = register.get_class_without_register(:string)
        expect(result).to eq(Lutaml::Model::Type::String)
      end
    end
  end

  describe ".lookup" do
    it "delegates to instance method" do
      expect(described_class.lookup(:default)).not_to be_nil
    end
  end

  describe "singleton behavior" do
    it "returns the same instance on multiple calls" do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end

    it "shares state between method calls" do
      register = Lutaml::Model::Register.new(:shared_test)
      described_class.register(register)
      expect(described_class.lookup(:shared_test)).not_to be_nil
      described_class.remove(:shared_test)
    end
  end

  describe "#remove" do
    let(:register_v_one) { Lutaml::Model::Register.new(:v1_remove_test) }
    let(:register_v_two) { Lutaml::Model::Register.new(:v2_remove_test) }

    before do
      described_class.register(register_v_one)
      described_class.register(register_v_two)
    end

    after do
      described_class.remove(:v1_remove_test) if described_class.lookup(:v1_remove_test)
      described_class.remove(:v2_remove_test) if described_class.lookup(:v2_remove_test)
    end

    it "removes the specified register" do
      expect(described_class.lookup(:v1_remove_test)).not_to be_nil
      described_class.remove(:v1_remove_test)
      expect(described_class.lookup(:v1_remove_test)).to be_nil
    end

    it "does not remove other registers" do
      described_class.remove(:v1_remove_test)
      expect(described_class.lookup(:v2_remove_test)).not_to be_nil
    end

    it "does nothing when the specified register does not exist" do
      expect { described_class.remove(:non_existent) }.not_to raise_error
    end
  end

  describe "GlobalContext fallback integration" do
    let(:context_id) { :fallback_integration_test }

    after do
      described_class.remove(context_id) if described_class.lookup(context_id)
      Lutaml::Model::GlobalContext.unregister_context(context_id)
    end

    context "when a model is registered only via GlobalContext" do
      let(:test_model) do
        klass = Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          json do
            map "name", to: :name
          end
        end
        # Stub a name so type resolution works
        stub_const("FallbackTestModel", klass)
        klass
      end

      before do
        registry = Lutaml::Model::TypeRegistry.new
        registry.register(:fallback_test_model, test_model)

        Lutaml::Model::GlobalContext.create_context(
          id: context_id,
          registry: registry,
          fallback_to: [:default],
        )
      end

      it "looks up the register via GlobalRegister and resolves the model" do
        register = described_class.lookup(context_id)
        expect(register).to be_a(Lutaml::Model::Register)

        result = register.get_class_without_register(:fallback_test_model)
        expect(result).to eq(test_model)
      end

      it "mapping register resolution finds the context-only register" do
        mapping = Lutaml::Model::Mapping.new
        register = mapping.send(:register, context_id)
        expect(register).to be_a(Lutaml::Model::Register)
        expect(register.id).to eq(context_id)
      end
    end

    context "when context does not exist in either GlobalRegister or GlobalContext" do
      it "returns nil" do
        expect(described_class.lookup(:totally_nonexistent)).to be_nil
      end
    end
  end
end
