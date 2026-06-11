# frozen_string_literal: true

require "spec_helper"
require "lutaml/store"

module ConversionCachingSpec
  class CachedModel < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :value, :string

    cache_conversions

    xml do
      root "cached-model"
      map_element "name", to: :name
      map_element "value", to: :value
    end
  end

  # Same root and shape as CachedModel: proves two cached classes
  # parsing identical input do not collide in the store.
  class TwinCachedModel < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :value, :string

    cache_conversions

    xml do
      root "cached-model"
      map_element "name", to: :name
      map_element "value", to: :value
    end
  end

  class UncachedModel < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      root "uncached-model"
      map_element "name", to: :name
    end
  end

  class InheritedModel < CachedModel
  end
end

RSpec.describe "Conversion caching" do
  let(:store) { Lutaml::Store::BasicStore.new(adapter: { type: :memory }) }

  after do
    Lutaml::Model::Config.conversion_cache = nil
  end

  describe "Config.conversion_cache" do
    it "defaults to a memory-backed BasicStore when lutaml-store is loaded" do
      expect(Lutaml::Model::Config.conversion_cache)
        .to be_a(Lutaml::Store::BasicStore)
    end

    it "is settable via the configure block" do
      Lutaml::Model::Config.configure do |config|
        config.conversion_cache = store
      end

      expect(Lutaml::Model::Config.conversion_cache).to be(store)
    end

    it "is disabled by assigning false" do
      Lutaml::Model::Config.conversion_cache = false

      expect(Lutaml::Model::Config.conversion_cache).to be_nil
    end
  end

  describe ".cache_conversions" do
    it "is disabled by default" do
      expect(ConversionCachingSpec::UncachedModel.conversion_caching_enabled?)
        .to be(false)
    end

    it "is enabled by the macro" do
      expect(ConversionCachingSpec::CachedModel.conversion_caching_enabled?)
        .to be(true)
    end

    it "is inherited by subclasses" do
      expect(ConversionCachingSpec::InheritedModel.conversion_caching_enabled?)
        .to be(true)
    end
  end

  describe "deserialization caching" do
    let(:xml) { "<cached-model><name>a</name><value>1</value></cached-model>" }

    before do
      Lutaml::Model::Config.conversion_cache = store
    end

    it "returns the cached instance for repeated identical input" do
      first = ConversionCachingSpec::CachedModel.from_xml(xml)
      second = ConversionCachingSpec::CachedModel.from_xml(xml)

      expect(second).to be(first)
    end

    it "uses the auto-detected default store when none is assigned" do
      Lutaml::Model::Config.conversion_cache = nil

      first = ConversionCachingSpec::CachedModel.from_xml(xml)
      second = ConversionCachingSpec::CachedModel.from_xml(xml)

      expect(second).to be(first)
      expect(Lutaml::Model::Config.conversion_cache.size).to eq(1)
    end

    it "does not cache when disabled with false" do
      Lutaml::Model::Config.conversion_cache = false

      first = ConversionCachingSpec::CachedModel.from_xml(xml)
      second = ConversionCachingSpec::CachedModel.from_xml(xml)

      expect(second).not_to be(first)
    end

    it "parses different input separately" do
      other = "<cached-model><name>b</name><value>2</value></cached-model>"

      first = ConversionCachingSpec::CachedModel.from_xml(xml)
      second = ConversionCachingSpec::CachedModel.from_xml(other)

      expect(second.name).to eq("b")
      expect(second).not_to be(first)
    end

    it "keeps same-named input separate per class" do
      cached = ConversionCachingSpec::CachedModel.from_xml(xml)
      twin = ConversionCachingSpec::TwinCachedModel.from_xml(xml)

      expect(twin).to be_a(ConversionCachingSpec::TwinCachedModel)
      expect(cached).to be_a(ConversionCachingSpec::CachedModel)
      expect(store.size).to eq(2)
    end

    it "caches calls that pass only the register option" do
      first = ConversionCachingSpec::CachedModel.from_xml(xml,
                                                          register: :default)
      second = ConversionCachingSpec::CachedModel.from_xml(xml,
                                                           register: :default)

      expect(second).to be(first)
    end

    it "caches calls with extra options under distinct keys" do
      plain = ConversionCachingSpec::CachedModel.from_xml(xml)
      opted = ConversionCachingSpec::CachedModel.from_xml(xml,
                                                          encoding: "UTF-8")
      again = ConversionCachingSpec::CachedModel.from_xml(xml,
                                                          encoding: "UTF-8")

      expect(store.size).to eq(2)
      expect(again).to be(opted)
      expect(opted).not_to be(plain)
    end

    it "treats a wrong-typed stored value as a miss" do
      ConversionCachingSpec::CachedModel.from_xml(xml)
      store.each_key { |key| store.set(key, "corrupted") }

      result = ConversionCachingSpec::CachedModel.from_xml(xml)

      expect(result).to be_a(ConversionCachingSpec::CachedModel)
      expect(result.name).to eq("a")
    end

    it "does not cache classes that did not opt in" do
      ConversionCachingSpec::UncachedModel.from_xml(
        "<uncached-model><name>a</name></uncached-model>",
      )

      expect(store.size).to eq(0)
    end

    it "lets store errors propagate instead of mislabeling them" do
      allow(store).to receive(:get).and_raise(TypeError, "store broke")

      expect do
        ConversionCachingSpec::CachedModel.from_xml(xml)
      end.to raise_error(TypeError, "store broke")
    end

    it "still raises InvalidFormatError for malformed input" do
      expect do
        ConversionCachingSpec::CachedModel.from_json("{not json")
      end.to raise_error(Lutaml::Model::InvalidFormatError)
    end
  end

  describe "serialization caching" do
    let(:instance) do
      ConversionCachingSpec::CachedModel.new(name: "a", value: "1")
    end

    before do
      Lutaml::Model::Config.conversion_cache = store
    end

    it "serves repeated serialization from the store" do
      instance.to_xml
      store.each_key { |key| store.set(key, "<sentinel/>") }

      expect(instance.to_xml).to eq("<sentinel/>")
    end

    it "re-serializes after the instance is mutated" do
      instance.to_xml
      instance.name = "b"

      expect(instance.to_xml).to include("b")
      expect(store.size).to eq(2)
    end

    it "caches each option set under its own key" do
      instance.to_xml
      instance.to_xml(pretty: true)

      expect(store.size).to eq(2)
    end

    it "bypasses for instances that cannot be marshaled" do
      instance.instance_variable_set(:@unmarshalable, proc {})

      expect(instance.to_xml).to include("<name>a</name>")
      expect(store.size).to eq(0)
    end

    it "does not cache classes that did not opt in" do
      ConversionCachingSpec::UncachedModel.new(name: "a").to_xml

      expect(store.size).to eq(0)
    end
  end

  describe "with Lutaml::Store::CacheStore" do
    let(:store) { Lutaml::Store::CacheStore.new(adapter: { type: :memory }) }
    let(:xml) { "<cached-model><name>a</name><value>1</value></cached-model>" }

    before do
      Lutaml::Model::Config.conversion_cache = store
    end

    it "serves to_* output strings through the JSON-marshaling store" do
      instance = ConversionCachingSpec::CachedModel.new(name: "a", value: "1")
      instance.to_xml
      # CacheStore has no #each_key; snapshot keys first.
      keys = store.keys
      keys.each { |key| store.set(key, "<sentinel/>") }

      expect(instance.to_xml).to eq("<sentinel/>")
    end

    it "recomputes from_* results that cannot round-trip through JSON" do
      first = ConversionCachingSpec::CachedModel.from_xml(xml)
      second = ConversionCachingSpec::CachedModel.from_xml(xml)

      expect(second).not_to be(first)
      expect(second.name).to eq("a")
    end
  end
end
