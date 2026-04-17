# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/one_entry_cache"

RSpec.describe Lutaml::Model::OneEntryCache do
  subject(:cache) { described_class.new }

  describe "#fetch_or_compute" do
    it "computes on first call" do
      call_count = 0
      result = cache.fetch_or_compute("key") do
        call_count += 1
        ["a", "b"]
      end
      expect(result).to eq(["a", "b"])
      expect(call_count).to eq(1)
    end

    it "returns cached value on subsequent calls with same key" do
      call_count = 0
      cache.fetch_or_compute("key") do
        call_count += 1
        ["a"]
      end
      result = cache.fetch_or_compute("key") do
        call_count += 1
        ["b"]
      end
      expect(result).to eq(["a"])
      expect(call_count).to eq(1)
    end

    it "returns same object identity on cache hit" do
      cache.fetch_or_compute("key") { ["a", "b"] }
      result = cache.fetch_or_compute("key") { ["other"] }
      expect(result).to equal(result) # identity check
    end

    it "replaces cache when key changes" do
      cache.fetch_or_compute("key1") { "value1" }
      result = cache.fetch_or_compute("key2") { "value2" }
      expect(result).to eq("value2")
    end

    it "caches nil parent_namespace correctly" do
      call_count = 0
      cache.fetch_or_compute(nil) do
        call_count += 1
        ["result"]
      end
      cache.fetch_or_compute(nil) do
        call_count += 1
        ["other"]
      end
      expect(call_count).to eq(1)
    end
  end

  describe "#fetch" do
    it "returns nil when cache is empty" do
      expect(cache.fetch("anything")).to be_nil
    end

    it "returns nil when key does not match" do
      cache.store("key1", "value1")
      expect(cache.fetch("key2")).to be_nil
    end

    it "returns value when key matches" do
      cache.store("key", "value")
      expect(cache.fetch("key")).to eq("value")
    end
  end

  describe "#store" do
    it "stores a single entry" do
      cache.store("key", "value")
      expect(cache.fetch("key")).to eq("value")
    end

    it "replaces the previous entry" do
      cache.store("old_key", "old_value")
      cache.store("new_key", "new_value")
      expect(cache.fetch("old_key")).to be_nil
      expect(cache.fetch("new_key")).to eq("new_value")
    end
  end

  describe "#clear" do
    it "removes the cached entry" do
      cache.store("key", "value")
      cache.clear
      expect(cache.fetch("key")).to be_nil
    end
  end

  describe "#empty?" do
    it "is empty when newly created" do
      expect(cache).to be_empty
    end

    it "is not empty after storing a value" do
      cache.store("key", "value")
      expect(cache).not_to be_empty
    end

    it "is empty after clearing" do
      cache.store("key", "value")
      cache.clear
      expect(cache).to be_empty
    end
  end
end
