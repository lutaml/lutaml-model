# frozen_string_literal: true

require "spec_helper"

# Compiled child-map walk plans (#986b): child_mappings rules ride the
# compiled dispatch (per-rule wire names, paths, and child type resolved
# once) instead of the per-node interpretive translate_mappings. Parity
# with the interpretive output is pinned here, including the
# keys-only merge rule (the merge tests the whole document hash, not
# each child) and the absent-key contract (the attribute stays
# uninitialized).
module ChildMapPlanSpec
  class Schema < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :path, :string
    attribute :name, :string
  end

  class Schemas < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :schemas, Schema, collection: true

    key_value do
      map "type", to: :type
      map "schemas", to: :schemas,
                     child_mappings: {
                       id: :key,
                       path: %i[path link],
                       name: %i[path name],
                     }
    end
  end

  class Entry < Lutaml::Model::Serializable
    attribute :key, :string
    attribute :value, :string
  end

  class EntryList < Lutaml::Model::Serializable
    attribute :title, :string
    attribute :entries, Entry, collection: true

    key_value do
      map "title", to: :title
      map "entries", to: :entries,
                     child_mappings: {
                       key: :key,
                       value: %i[detail text],
                     }
    end
  end

  class Tag < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :count, :integer
  end

  class Tags < Lutaml::Model::Serializable
    attribute :tags, Tag, collection: true

    key_value do
      map "tags", to: :tags,
                  child_mappings: {
                    name: :key,
                    count: :value,
                  }
    end
  end

  class KeyedChild < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :label, :string
    attribute :extra, :hash

    key_value do
      map "id", to: :id
      map "label", to: :label
      map_unmapped to: :extra
    end
  end

  class KeyOnly < Lutaml::Model::Serializable
    attribute :items, KeyedChild, collection: true

    key_value do
      map "items", to: :items,
                   child_mappings: { id: :key }
    end
  end

  RSpec.describe "compiled child_mappings walk plans" do
    it "translates explicit-path child mappings into child models" do
      model = Schemas.from_json(
        '{"type":"object","schemas":{' \
        '"sch1":{"path":{"link":"https://one","name":"one"}},' \
        '"sch2":{"path":{"link":"https://two","name":"two"}}}}',
      )

      expect(model.schemas.map(&:id)).to eq(%w[sch1 sch2])
      expect(model.schemas.first.path).to eq("https://one")
      expect(model.schemas.last.name).to eq("two")
    end

    it "round-trips the translated wire form" do
      json = '{"type":"object","schemas":{' \
             '"sch1":{"path":{"link":"https://one","name":"one"}}}}'
      model = Schemas.from_json(json)

      expect(model.to_json).to eq(json)
      expect(model.to_json).to eq(json) # warm-plan second pass
    end

    it "translates value paths" do
      model = EntryList.from_json(
        '{"title":"list","entries":{' \
        '"e1":{"detail":{"text":"first"}},' \
        '"e2":{"detail":{"text":"second"}}}}',
      )

      expect(model.entries.map(&:key)).to eq(%w[e1 e2])
      expect(model.entries.first.value).to eq("first")
    end

    it "casts values through the child attribute types" do
      model = Tags.from_json('{"tags":{"red":3,"blue":5}}')

      expect(model.tags.map(&:name)).to eq(%w[red blue])
      expect(model.tags.map(&:count)).to eq([3, 5])
    end

    it "keeps the attribute uninitialized when the key is absent" do
      model = Schemas.from_json('{"type":"object"}')

      expect(model.type).to eq("object")
      expect(model.schemas).to be_nil
    end

    it "handles an empty mapping value" do
      model = Schemas.from_json('{"type":"object","schemas":{}}')

      expect(model.schemas).to eq([])
    end

    it "merges unmapped keys only when every value in the hash is a hash" do
      model = KeyOnly.from_json(
        '{"items":{"a":{"label":"A","extra":1},"b":{"label":"B"}}}',
      )

      expect(model.items.map(&:id)).to eq(%w[a b])
      expect(model.items.first.label).to eq("A")
      expect(model.items.first.extra).to eq("extra" => 1)
    end

    it "skips the merge when any value in the hash is not a hash" do
      model = KeyOnly.from_json('{"items":{"a":"plain","b":{"label":"B"}}}')

      expect(model.items.first.id).to eq("a")
      expect(model.items.first.extra).to be_nil
      expect(model.items.last.id).to eq("b")
      expect(model.items.last.label).to be_nil
    end

    it "serializes a keyed collection through the compiled plan" do
      model = Tags.from_json('{"tags":{"red":3}}')

      expect(model.to_json).to eq('{"tags":{"red":3}}')
    end
  end
end
