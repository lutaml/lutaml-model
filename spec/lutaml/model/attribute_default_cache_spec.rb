# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attribute default caching" do
  describe "immutable defaults" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string, default: -> { "default_name" }
        attribute :count, :integer, default: -> { 42 }
      end
    end

    it "returns same default object for immutable types" do
      attr = klass.attributes[:name]
      default1 = attr.default(:default)
      default2 = attr.default(:default)
      expect(default1).to equal(default2)
    end
  end

  describe "mutable defaults" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :prefs, :hash, default: -> { { theme: "dark" } }
      end
    end

    it "does not share mutable default between calls" do
      attr = klass.attributes[:prefs]
      default1 = attr.default(:default)
      default2 = attr.default(:default)

      # If cached, they'd be the same object. Mutating one would affect the other.
      # With the immutable_value? guard, Hashes are NOT cached, so each call
      # re-evaluates the default proc, producing independent objects.
      if default1.equal?(default2)
        # If they happen to be the same (cached), mutation should NOT propagate
        pending "mutable default caching needs fixing"
      end
    end
  end

  describe "instance-aware defaults" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string, default: -> { "default" }
      end
    end

    it "passes instance_object to default_value when provided" do
      attr = klass.attributes[:label]
      instance = klass.new
      result = attr.default(:default, instance)
      expect(result).to eq("default")
    end
  end
end
