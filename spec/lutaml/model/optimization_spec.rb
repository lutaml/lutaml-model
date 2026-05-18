# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Optimization behaviors" do
  before do
    Lutaml::Model::GlobalContext.clear_caches
    Lutaml::Model::TransformationRegistry.instance.clear
    Lutaml::Model::GlobalRegister.instance.reset
    Lutaml::Model::Store.clear
  end

  after do
    Lutaml::Model::GlobalContext.clear_caches
    Lutaml::Model::TransformationRegistry.instance.clear
    Lutaml::Model::GlobalRegister.instance.reset
    Lutaml::Model::Store.clear
  end

  describe "DeserializationContext propagation" do
    let(:propagation_keys) do
      Lutaml::Model::Serialize::DeserializationContext::PROPAGATION_KEYS
    end

    it "propagates only whitelisted keys" do
      options = {
        lutaml_parent: "parent",
        lutaml_root: "root",
        default_namespace: "http://example.com",
        namespace_uri: "http://internal.com",
        resolved_type: String,
        converted: true,
        polymorphic: :by_type,
        collection: true,
      }

      propagated = Lutaml::Model::Serialize::DeserializationContext.propagate(options)

      expect(propagated).to eq({
                                 lutaml_parent: "parent",
                                 lutaml_root: "root",
                                 default_namespace: "http://example.com",
                                 polymorphic: :by_type,
                                 collection: true,
                               })
    end

    it "excludes parent-internal keys" do
      options = {
        namespace_uri: "http://internal.com",
        resolved_type: String,
        converted: true,
        mappings: double("mappings"),
      }

      propagated = Lutaml::Model::Serialize::DeserializationContext.propagate(options)

      expect(propagated).to be_empty
    end

    it "CHILD_PROPAGATION_KEYS matches PROPAGATION_KEYS" do
      expect(Lutaml::Model::Attribute::CHILD_PROPAGATION_KEYS).to eq(propagation_keys)
    end
  end

  describe "conditional reference store registration" do
    it "registers instances by default" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
      end

      obj = klass.new(id: "test")
      result = Lutaml::Model::Store.resolve(klass, :id, "test")
      expect(result).to eq(obj)
    end

    it "skips registration when skip_reference_registration is declared" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        skip_reference_registration
      end

      klass.new(id: "test")
      result = Lutaml::Model::Store.resolve(klass, :id, "test")
      expect(result).to be_nil
    end

    it "reference_resolvable? returns true by default" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
      end

      expect(klass.reference_resolvable?).to be true
    end

    it "reference_resolvable? returns false after skip_reference_registration" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        skip_reference_registration
      end

      expect(klass.reference_resolvable?).to be false
    end

    it "skips registration during allocate_for_deserialization" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :string
        skip_reference_registration
      end

      instance = klass.allocate_for_deserialization
      instance.public_send(:id=, "deserialized")
      result = Lutaml::Model::Store.resolve(klass, :id, "deserialized")
      expect(result).to be_nil
    end
  end

  describe "class_attributes accessor" do
    it "returns raw attributes without register merging" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      expect(klass.class_attributes).to be_a(Hash)
      expect(klass.class_attributes.keys).to include(:name)
    end
  end

  describe "MappingRule#static_namespace_option" do
    it "returns frozen hash for rules with explicit namespace" do
      rule = Lutaml::Xml::MappingRule.new(
        "test",
        to: :test,
        namespace: ExampleComNamespace,
        namespace_set: true,
      )

      result = rule.static_namespace_option
      expect(result).to eq({ default_namespace: "http://example.com" })
      expect(result).to be_frozen
    end

    it "returns the same object on repeated calls (cached)" do
      rule = Lutaml::Xml::MappingRule.new(
        "test",
        to: :test,
        namespace: ExampleComNamespace,
        namespace_set: true,
      )

      first = rule.static_namespace_option
      second = rule.static_namespace_option
      expect(first).to equal(second) # same object identity
    end

    it "returns nil when no namespace is set" do
      rule = Lutaml::Xml::MappingRule.new("test", to: :test)

      expect(rule.static_namespace_option).to be_nil
    end

    it "returns nil when namespace is :inherit" do
      rule = Lutaml::Xml::MappingRule.new(
        "test",
        to: :test,
        namespace: :inherit,
      )

      expect(rule.static_namespace_option).to be_nil
    end
  end

  describe "String deduplication in namespace URIs" do
    it "XmlElement#namespace_uri deduplicates via unary minus" do
      ns_instance = ExampleComNamespace.new
      parent = Lutaml::Xml::XmlElement.new(nil, {}, [], nil,
                                           name: "root",
                                           parent_document: double(namespaces: { nil => ns_instance }))
      uri = parent.namespace_uri

      # The returned string should be the deduplicated version (-uri)
      expect(uri).to eq("http://example.com")
      expect(uri).to be_frozen
    end

    it "XmlElement#namespaced_name deduplicates the result string" do
      ExampleComNamespace.new
      parent = Lutaml::Xml::XmlElement.new(nil, {}, [], nil,
                                           name: "root",
                                           default_namespace: "http://example.com",
                                           parent_document: double(namespaces: {}))
      result = parent.namespaced_name

      expect(result).to eq("http://example.com:root")
      expect(result).to be_frozen
    end
  end

  describe "value_set_for" do
    it "transitions from nil (all defaults) to per-attribute tracking" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :age, :integer
      end

      obj = klass.allocate_for_deserialization
      expect(obj.using_default?(:name)).to be true
      expect(obj.using_default?(:age)).to be true

      obj.value_set_for(:name)
      expect(obj.using_default?(:name)).to be false
      expect(obj.using_default?(:age)).to be true
    end

    it "values_set_for sets multiple attributes at once" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :age, :integer
      end

      obj = klass.allocate_for_deserialization
      obj.values_set_for(%i[name age])

      expect(obj.using_default?(:name)).to be false
      expect(obj.using_default?(:age)).to be false
    end
  end
end
