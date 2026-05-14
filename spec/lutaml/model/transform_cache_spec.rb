# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Transform caching" do
  after { Lutaml::Model::Transform.clear_cache! }

  describe ".cached_transform" do
    it "returns same instance for same context and register" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      t1 = Lutaml::Model::Transform.cached_transform(klass, :default)
      t2 = Lutaml::Model::Transform.cached_transform(klass, :default)
      expect(t1).to equal(t2)
    end

    it "returns different instances for different contexts" do
      klass_a = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end
      klass_b = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
      end

      t1 = Lutaml::Model::Transform.cached_transform(klass_a, :default)
      t2 = Lutaml::Model::Transform.cached_transform(klass_b, :default)
      expect(t1).not_to equal(t2)
    end
  end

  describe ".clear_cache!" do
    it "clears the cache" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      Lutaml::Model::Transform.cached_transform(klass, :default)
      expect(Lutaml::Model::Transform.cache_size).to be > 0

      Lutaml::Model::Transform.clear_cache!
      expect(Lutaml::Model::Transform.cache_size).to eq(0)
    end
  end

  describe "cache eviction" do
    it "evicts entries when exceeding MAX_CACHE_SIZE" do
      stub_const("Lutaml::Model::Transform::MAX_CACHE_SIZE", 4)

      classes = Array.new(6) do |i|
        Class.new(Lutaml::Model::Serializable) do
          attribute :"attr_#{i}", :string
        end
      end

      classes.each { |k| Lutaml::Model::Transform.cached_transform(k, :default) }

      expect(Lutaml::Model::Transform.cache_size).to be <= 4
    end
  end

  describe ".invalidate_for" do
    it "invalidates cache for a specific context" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      t1 = Lutaml::Model::Transform.cached_transform(klass, :default)
      Lutaml::Model::Transform.invalidate_for(klass)
      t2 = Lutaml::Model::Transform.cached_transform(klass, :default)
      expect(t1).not_to equal(t2)
    end

    it "invalidates cache for a specific context and register" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      t1_default = Lutaml::Model::Transform.cached_transform(klass, :default)
      t1_other = Lutaml::Model::Transform.cached_transform(klass, :other)

      Lutaml::Model::Transform.invalidate_for(klass, :default)

      t2_default = Lutaml::Model::Transform.cached_transform(klass, :default)
      t2_other = Lutaml::Model::Transform.cached_transform(klass, :other)

      expect(t1_default).not_to equal(t2_default)
      expect(t1_other).to equal(t2_other)
    end

    it "uses class identity as key, not object_id" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      t1 = Lutaml::Model::Transform.cached_transform(klass, :default)
      # Force GC — object_id reuse should not cause stale hits
      GC.start
      t2 = Lutaml::Model::Transform.cached_transform(klass, :default)
      expect(t1).to equal(t2)
    end
  end
end
