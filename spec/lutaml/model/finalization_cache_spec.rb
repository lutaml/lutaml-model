# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/finalization_cache"

RSpec.describe Lutaml::Model::FinalizationCache do
  subject(:cache) { described_class.new }

  describe "before finalization" do
    it "is not finalized" do
      expect(cache).not_to be_finalized
    end

    it "computes but does not cache" do
      call_count = 0
      r1 = cache.fetch_or_store(:key) { call_count += 1; [1, 2, 3] }
      r2 = cache.fetch_or_store(:key) { call_count += 1; [4, 5, 6] }
      expect(r1).to eq([1, 2, 3])
      expect(r2).to eq([4, 5, 6])
      expect(call_count).to eq(2)
    end

    it "returns unfrozen results" do
      result = cache.fetch_or_store(:key) { [1, 2, 3] }
      expect(result).not_to be_frozen
    end
  end

  describe "after finalization" do
    before { cache.finalize! }

    it "is finalized" do
      expect(cache).to be_finalized
    end

    it "caches and returns the same object on repeated calls" do
      call_count = 0
      cache.fetch_or_store(:key) { call_count += 1; [1, 2, 3] }
      result = cache.fetch_or_store(:key) { call_count += 1; [4, 5, 6] }
      expect(result).to eq([1, 2, 3])
      expect(call_count).to eq(1)
    end

    it "freezes cached results" do
      result = cache.fetch_or_store(:key) { [1, 2, 3] }
      expect(result).to be_frozen
    end

    it "caches per key independently" do
      cache.fetch_or_store(:a) { "value_a" }
      cache.fetch_or_store(:b) { "value_b" }
      expect(cache.fetch(:a)).to eq("value_a")
      expect(cache.fetch(:b)).to eq("value_b")
    end
  end

  describe "#finalize!" do
    it "clears stale entries before setting finalized" do
      # Simulate pre-finalization entries by populating the store directly
      cache.instance_variable_get(:@store)[:stale] = "old_value"
      cache.finalize!
      expect(cache.fetch(:stale)).to be_nil
      expect(cache).to be_finalized
    end
  end

  describe "#clear" do
    it "clears entries without changing finalized status" do
      cache.finalize!
      cache.fetch_or_store(:key) { "value" }
      cache.clear
      expect(cache.fetch(:key)).to be_nil
      expect(cache).to be_finalized
    end
  end
end
