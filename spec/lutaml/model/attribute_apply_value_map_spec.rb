require "spec_helper"

RSpec.describe Lutaml::Model::Attribute, "#apply_value_map" do
  def attribute(type, **opts)
    described_class.new("attr", type, **opts)
  end

  let(:uninit) { Lutaml::Model::UninitializedClass.instance }

  describe "nil handling" do
    it "maps nil through value_map[:nil] => :nil" do
      expect(attribute(:string).apply_value_map(nil, { nil: :nil })).to be_nil
    end

    it "maps nil through value_map[:nil] => :empty to '' (scalar)" do
      expect(attribute(:string).apply_value_map(nil, { nil: :empty })).to eq("")
    end

    it "maps nil through value_map[:nil] => :empty to [] (collection)" do
      expect(
        attribute(:string, collection: true).apply_value_map(nil, { nil: :empty }),
      ).to eq([])
    end

    it "maps nil through value_map[:nil] => :empty to a custom collection class instance" do
      # Regression: pre-consolidation Serialize::ValueMapping#empty_object used
      # attr.build_collection (preserving custom collection class). The
      # consolidated Attribute#apply_value_map must also use build_collection,
      # not literal [], so attributes typed with a Lutaml::Model::Collection
      # subclass don't silently downgrade to plain Array during model init.
      member_class = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end
      custom_collection_class = Class.new(Lutaml::Model::Collection) do
        instances :items, member_class
      end
      attr = described_class.new("items", member_class, collection: custom_collection_class)
      result = attr.apply_value_map(nil, { nil: :empty })
      expect(result).to be_a(custom_collection_class)
    end

    it "maps nil through value_map[:nil] => :omitted to UninitializedClass" do
      expect(attribute(:string).apply_value_map(nil, { nil: :omitted })).to eq(uninit)
    end
  end

  describe "empty handling" do
    it "maps '' through value_map[:empty] => :nil" do
      expect(attribute(:string).apply_value_map("", { empty: :nil })).to be_nil
    end

    it "maps '' through value_map[:empty] => :empty preserving '' for scalar" do
      expect(attribute(:string).apply_value_map("", { empty: :empty })).to eq("")
    end

    it "maps [] through value_map[:empty] => :empty preserving [] for collection" do
      expect(
        attribute(:string, collection: true).apply_value_map([], { empty: :empty }),
      ).to eq([])
    end

    it "maps {} through value_map[:empty] => :empty preserving {} for Hash attribute" do
      # Regression: must preserve the input type when source key matches the
      # :empty mapping. Original value_for_option used `empty_value ||
      # empty_object(attr)` which returned the truthy {} unchanged.
      expect(attribute(:hash).apply_value_map({}, { empty: :empty })).to eq({})
    end
  end

  describe "omitted handling" do
    it "maps UninitializedClass through value_map[:omitted] => :nil" do
      expect(attribute(:string).apply_value_map(uninit, { omitted: :nil })).to be_nil
    end

    it "maps UninitializedClass through value_map[:omitted] => :empty" do
      expect(attribute(:string).apply_value_map(uninit, { omitted: :empty })).to eq("")
    end

    it "does NOT route UninitializedClass through the :empty branch" do
      # Regression: Utils.empty?(UninitializedClass.instance) is false per
      # utils.rb:132-137. Ensure dispatch order matches the originals: uninit
      # values go to :omitted, not :empty.
      expect(
        attribute(:string).apply_value_map(uninit, { empty: :nil, omitted: :empty }),
      ).to eq("")
    end
  end

  describe "Boolean bare-form (Boolean attribute type required)" do
    it "returns false directly for Boolean attribute, value_map[:empty] = false" do
      expect(attribute(:boolean).apply_value_map("", { empty: false })).to be(false)
    end

    it "returns true directly for Boolean attribute, value_map[:omitted] = true" do
      expect(attribute(:boolean).apply_value_map(uninit, { omitted: true })).to be(true)
    end

    it "does NOT apply bare-boolean form to a non-Boolean attribute (documented tightening)" do
      # Plan §"Hidden behavior change" — bare-boolean form requires Boolean type.
      # Falls through to the :empty option dispatch, which for an unknown option
      # returns UninitializedClass.instance.
      result = attribute(:string).apply_value_map("", { empty: false })
      expect(result).to eq(uninit)
    end
  end

  describe "Boolean nested-form (value_map[:from][:empty] / [:omitted])" do
    it "returns false from value_map[:from][:empty] unconditionally for Boolean attribute" do
      expect(attribute(:boolean).apply_value_map("", { from: { empty: false } })).to be(false)
    end

    it "returns true from value_map[:from][:omitted] unconditionally for Boolean attribute" do
      expect(attribute(:boolean).apply_value_map(uninit, { from: { omitted: true } })).to be(true)
    end

    it "returns false from nested form even for non-Boolean attribute (no type gate)" do
      expect(attribute(:string).apply_value_map("", { from: { empty: false } })).to be(false)
    end
  end

  describe "pass-through" do
    it "returns the value untouched when present and non-empty" do
      expect(attribute(:string).apply_value_map("hello", {})).to eq("hello")
    end

    it "returns Boolean false untouched (real value, not 'empty')" do
      expect(attribute(:boolean).apply_value_map(false, {})).to be(false)
    end

    it "returns Boolean true untouched" do
      expect(attribute(:boolean).apply_value_map(true, {})).to be(true)
    end
  end
end
