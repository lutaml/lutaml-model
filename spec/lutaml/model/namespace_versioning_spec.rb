# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::NamespaceBinding do
  let(:namespace_class) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/test/20131001"
      prefix_default "test"
    end
  end

  describe "#initialize" do
    it "creates a binding with register_id and namespace_class" do
      binding = described_class.new(
        register_id: :test_register,
        namespace_class: namespace_class,
      )

      expect(binding.register_id).to eq(:test_register)
      expect(binding.namespace_class).to eq(namespace_class)
      expect(binding.namespace_uri).to eq("http://example.com/test/20131001")
    end

    it "is frozen after creation" do
      binding = described_class.new(
        register_id: :test,
        namespace_class: namespace_class,
      )

      expect(binding).to be_frozen
    end
  end

  describe "#==" do
    it "is equal if register_id and namespace_uri match" do
      binding1 = described_class.new(
        register_id: :test,
        namespace_class: namespace_class,
      )
      binding2 = described_class.new(
        register_id: :test,
        namespace_class: namespace_class,
      )

      expect(binding1).to eq(binding2)
    end

    it "is not equal if register_id differs" do
      binding1 = described_class.new(
        register_id: :test1,
        namespace_class: namespace_class,
      )
      binding2 = described_class.new(
        register_id: :test2,
        namespace_class: namespace_class,
      )

      expect(binding1).not_to eq(binding2)
    end
  end

  describe "#hash" do
    it "can be used as hash key" do
      binding = described_class.new(
        register_id: :test,
        namespace_class: namespace_class,
      )

      hash = { binding => "value" }
      expect(hash[binding]).to eq("value")
    end
  end
end

RSpec.describe Lutaml::Model::ModelTreeImporter do
  let(:register) { Lutaml::Model::Register.new(:importer_test) }

  before do
    Lutaml::Model::GlobalContext.reset!
    Lutaml::Model::GlobalRegister.register(register)
  end

  after do
    Lutaml::Model::GlobalRegister.unregister(register.id)
  end

  describe "#import" do
    context "with a simple model" do
      let(:simple_model) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :value, :integer

          xml do
            root "Simple"
            map_element "name", to: :name
            map_element "value", to: :value
          end
        end
      end

      it "registers the model" do
        importer = described_class.new(register)
        registered = importer.import(simple_model)

        expect(registered).to include(simple_model)
        expect(register.models.values).to include(simple_model)
      end
    end
  end
end

RSpec.describe "Register Namespace Binding" do
  let(:namespace_v1) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/v1"
      prefix_default "v1"
    end
  end

  let(:namespace_v2) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/v2"
      prefix_default "v2"
    end
  end

  before { Lutaml::Model::GlobalContext.reset! }
  after { Lutaml::Model::GlobalContext.reset! }

  describe "#bind_namespace" do
    let(:register) { Lutaml::Model::Register.new(:ns_test) }

    before { Lutaml::Model::GlobalRegister.register(register) }
    after { Lutaml::Model::GlobalRegister.unregister(register.id) }

    it "binds register to namespace class" do
      binding = register.bind_namespace(namespace_v1)

      expect(binding).to be_a(Lutaml::Model::NamespaceBinding)
      expect(binding.register_id).to eq(:ns_test)
      expect(binding.namespace_uri).to eq("http://example.com/v1")
    end

    it "appears in bound_namespace_uris" do
      register.bind_namespace(namespace_v1)
      register.bind_namespace(namespace_v2)

      expect(register.bound_namespace_uris).to contain_exactly(
        "http://example.com/v1",
        "http://example.com/v2",
      )
    end

    it "registers in GlobalContext" do
      register.bind_namespace(namespace_v1)

      expect(Lutaml::Model::GlobalContext.register_id_for_namespace("http://example.com/v1"))
        .to eq(:ns_test)
    end
  end

  describe "#handles_namespace?" do
    let(:register) { Lutaml::Model::Register.new(:handles_test) }

    before { Lutaml::Model::GlobalRegister.register(register) }
    after { Lutaml::Model::GlobalRegister.unregister(register.id) }

    it "returns true for bound namespace" do
      register.bind_namespace(namespace_v1)
      expect(register.handles_namespace?("http://example.com/v1")).to be true
    end

    it "returns false for unbound namespace" do
      expect(register.handles_namespace?("http://example.com/unknown")).to be false
    end
  end
end

RSpec.describe "GlobalContext Namespace Mapping" do
  before { Lutaml::Model::GlobalContext.reset! }
  after { Lutaml::Model::GlobalContext.reset! }

  describe "#register_for_namespace" do
    let(:register) { Lutaml::Model::Register.new(:ns_map_test) }

    before { Lutaml::Model::GlobalRegister.register(register) }
    after { Lutaml::Model::GlobalRegister.unregister(register.id) }

    it "returns register bound to namespace" do
      namespace = Class.new(Lutaml::Xml::Namespace) do
        uri "http://test.example.com/ns"
        prefix_default "t"
      end

      register.bind_namespace(namespace)

      result = Lutaml::Model::GlobalContext.register_for_namespace("http://test.example.com/ns")
      expect(result).to eq(register)
    end

    it "returns nil for unbound namespace" do
      result = Lutaml::Model::GlobalContext.register_for_namespace("http://unknown.example.com/ns")
      expect(result).to be_nil
    end
  end
end

RSpec.describe "Register Fallback Chain with Namespaces" do
  before do
    Lutaml::Model::GlobalContext.reset!
    Lutaml::Model::GlobalRegister.register(common_register)
    Lutaml::Model::GlobalRegister.register(v1_register)
    Lutaml::Model::GlobalRegister.register(v2_register)

    v1_register.bind_namespace(ns_v1)
    v2_register.bind_namespace(ns_v2)

    common_register.register_model(common_model, id: :shared_model)
    v1_register.register_model(v1_only_model, id: :v1_model)
    v2_register.register_model(v2_only_model, id: :v2_model)
  end

  after do
    Lutaml::Model::GlobalContext.reset!
    Lutaml::Model::GlobalRegister.unregister(common_register.id)
    Lutaml::Model::GlobalRegister.unregister(v1_register.id)
    Lutaml::Model::GlobalRegister.unregister(v2_register.id)
  end

  let(:common_register) { Lutaml::Model::Register.new(:common_ns, fallback: [:default]) }
  let(:v1_register) { Lutaml::Model::Register.new(:v1_ns, fallback: %i[common_ns default]) }
  let(:v2_register) { Lutaml::Model::Register.new(:v2_ns, fallback: %i[v1_ns common_ns default]) }

  let(:ns_v1) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/v1"
      prefix_default "v1"
    end
  end

  let(:ns_v2) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/v2"
      prefix_default "v2"
    end
  end

  let(:common_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :shared, :string
    end
  end

  let(:v1_only_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :v1_only, :string
    end
  end

  let(:v2_only_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :v2_only, :string
    end
  end

  describe "#resolve_in_namespace" do
    it "finds type in own register" do
      result = v2_register.resolve_in_namespace(:v2_model, "http://example.com/v2")
      expect(result).to eq(v2_only_model)
    end

    it "finds type via fallback chain" do
      # v2 can find v1 model via fallback
      result = v2_register.resolve_in_namespace(:v1_model, "http://example.com/v2")
      expect(result).to eq(v1_only_model)
    end

    it "finds common type via deep fallback" do
      # v2 can find common model via v1 -> common fallback
      result = v2_register.resolve_in_namespace(:shared_model, "http://example.com/v2")
      expect(result).to eq(common_model)
    end

    it "returns nil for unknown type" do
      result = v2_register.resolve_in_namespace(:unknown_type, "http://example.com/v2")
      expect(result).to be_nil
    end
  end
end
