# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::TypeSubstitution do
  let(:from_class) { Class.new }
  let(:to_class) { Class.new }
  let(:substitution) { described_class.new(from_type: from_class, to_type: to_class) }

  describe "#initialize" do
    it "stores from_type and to_type" do
      expect(substitution.from_type).to eq(from_class)
      expect(substitution.to_type).to eq(to_class)
    end

    it "is frozen (immutable)" do
      expect(substitution.frozen?).to be true
    end
  end

  describe "#applies_to?" do
    it "returns true when the class matches from_type" do
      expect(substitution.applies_to?(from_class)).to be true
    end

    it "returns false when the class does not match from_type" do
      other_class = Class.new
      expect(substitution.applies_to?(other_class)).to be false
    end

    it "returns false for nil" do
      expect(substitution.applies_to?(nil)).to be false
    end
  end

  describe "#apply" do
    it "returns to_type when applies_to? is true" do
      result = substitution.apply(from_class)
      expect(result).to eq(to_class)
    end

    it "returns nil when applies_to? is false" do
      other_class = Class.new
      result = substitution.apply(other_class)
      expect(result).to be_nil
    end
  end

  describe "#==" do
    it "returns true for identical substitutions" do
      other = described_class.new(from_type: from_class, to_type: to_class)
      expect(substitution == other).to be true
    end

    it "returns false for different from_type" do
      other_from = Class.new
      other = described_class.new(from_type: other_from, to_type: to_class)
      expect(substitution == other).to be false
    end

    it "returns false for different to_type" do
      other_to = Class.new
      other = described_class.new(from_type: from_class, to_type: other_to)
      expect(substitution == other).to be false
    end

    it "returns false for non-TypeSubstitution objects" do
      expect(substitution == "string").to be false
      expect(substitution == nil).to be false
      expect(substitution == from_class).to be false
    end
  end

  describe "#eql?" do
    it "is an alias for ==" do
      other = described_class.new(from_type: from_class, to_type: to_class)
      expect(substitution.eql?(other)).to be true
    end
  end

  describe "#hash" do
    it "returns the same hash for equal substitutions" do
      other = described_class.new(from_type: from_class, to_type: to_class)
      expect(substitution.hash).to eq(other.hash)
    end

    it "allows use as hash keys" do
      hash = {}
      hash[substitution] = "value"

      other = described_class.new(from_type: from_class, to_type: to_class)
      expect(hash[other]).to eq("value")
    end
  end

  describe "#to_s" do
    it "returns a human-readable representation" do
      result = substitution.to_s
      expect(result).to include("TypeSubstitution")
      expect(result).to include("=>")
    end
  end

  describe "#inspect" do
    it "is an alias for to_s" do
      expect(substitution.inspect).to eq(substitution.to_s)
    end
  end

  describe "#with" do
    it "creates a copy with new from_type" do
      new_from = Class.new
      new_sub = substitution.with(from_type: new_from)

      expect(new_sub.from_type).to eq(new_from)
      expect(new_sub.to_type).to eq(to_class)
      expect(new_sub).not_to eq(substitution)
    end

    it "creates a copy with new to_type" do
      new_to = Class.new
      new_sub = substitution.with(to_type: new_to)

      expect(new_sub.from_type).to eq(from_class)
      expect(new_sub.to_type).to eq(new_to)
      expect(new_sub).not_to eq(substitution)
    end

    it "creates an identical copy with no arguments" do
      new_sub = substitution.with

      expect(new_sub.from_type).to eq(from_class)
      expect(new_sub.to_type).to eq(to_class)
      expect(new_sub).to eq(substitution)
    end
  end

  describe "value object semantics" do
    it "can be used in Set" do
      set = Set.new
      set << substitution
      set << described_class.new(from_type: from_class, to_type: to_class)

      expect(set.size).to eq(1)
    end

    it "can be used as hash key" do
      hash = {}
      hash[substitution] = "first"
      hash[described_class.new(from_type: from_class, to_type: to_class)] = "second"

      expect(hash.size).to eq(1)
      expect(hash[substitution]).to eq("second")
    end
  end

  describe "integration with real type classes" do
    it "can substitute custom type with built-in type" do
      custom_text = Class.new(Lutaml::Model::Type::String)
      sub = described_class.new(
        from_type: custom_text,
        to_type: Lutaml::Model::Type::String
      )

      expect(sub.applies_to?(custom_text)).to be true
      expect(sub.apply(custom_text)).to eq(Lutaml::Model::Type::String)
    end
  end
end
