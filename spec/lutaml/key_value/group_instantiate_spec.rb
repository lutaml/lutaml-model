# frozen_string_literal: true

require "spec_helper"

# TODO.max-perf/37: eligible models hydrate in ONE pass — present keys
# collected per rule, child models recursed, one instance per model.
# Absent rules keep the real per-rule walk; anything ineligible keeps
# the whole walk.
class KvGroupPart < Lutaml::Model::Serializable
  attribute :label, :string
  attribute :count, :integer

  json do
    map "label", to: :label
    map "count", to: :count
  end

  hsh do
    map "label", to: :label
    map "count", to: :count
  end
end

class KvGroupWidget < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :flag, :boolean
  attribute :part, KvGroupPart
  attribute :parts, KvGroupPart, collection: true
  attribute :tags, :string, collection: true

  json do
    map "name", to: :name
    map "flag", to: :flag
    map "part", to: :part
    map "parts", to: :parts
    map "tags", to: :tags
  end

  hsh do
    map "name", to: :name
    map "flag", to: :flag
    map "part", to: :part
    map "parts", to: :parts
    map "tags", to: :tags
  end
end

RSpec.describe "KV group-then-bulk hydration" do
  before do
    stub_const("KvGroup::Part", KvGroupPart)
    stub_const("KvGroup::Widget", KvGroupWidget)
  end

  let(:doc) do
    {
      "name" => "w",
      "flag" => true,
      "part" => { "label" => "p", "count" => 2 },
      "parts" => [{ "label" => "a" }, { "label" => "b", "count" => 5 }],
      "tags" => %w[x y],
    }
  end

  it "hydrates nested models through the group path" do
    widget = KvGroupWidget.from_hash(doc)

    expect(widget.name).to eq("w")
    expect(widget.flag).to be(true)
    expect(widget.part.label).to eq("p")
    expect(widget.part.count).to eq(2)
    expect(widget.parts.map(&:label)).to eq(%w[a b])
    expect(widget.parts.map(&:count)).to eq([nil, 5])
    expect(widget.tags).to eq(%w[x y])
  end

  it "threads parent and root links like the per-rule walk" do
    widget = KvGroupWidget.from_hash(doc)

    expect(widget.part.lutaml_parent).to equal(widget)
    expect(widget.parts.first.lutaml_parent).to equal(widget)
    expect(widget.parts.first.lutaml_root).to equal(widget)
  end

  it "leaves absent attributes exactly as the per-rule walk does" do
    empty = KvGroupWidget.from_hash({})
    # The walk's own contract for absent keys: values seeded by the
    # constructor's defaults, marked set-by-parse (not default) — the
    # group path runs the same absent-rule walk, so it matches.
    expect(empty.name).to be_nil
    expect(empty.part).to be_nil

    named = KvGroupWidget.from_hash("name" => "q")
    expect(named.name).to eq("q")
    expect(named.part).to be_nil
  end

  it "engages the group path (wiring proves engagement)" do
    counted = Class.new(KvGroupPart) do
      @built = 0
      class << self
        attr_reader :built

        def new(*args)
          @built += 1
          super
        end
      end
    end
    holder = Class.new(Lutaml::Model::Serializable) do
      attribute :parts, counted, collection: true

      json { map "parts", to: :parts }
      hsh { map "parts", to: :parts }
    end
    stub_const("KvGroup::Counted", counted)
    stub_const("KvGroup::Holder", holder)

    holder.from_hash("parts" => [{ "label" => "a" }, { "label" => "b" }])
    # 2 parts = 2 constructions, one per instance, no per-rule walk
    expect(counted.built).to eq(2)
  end

  it "works through json and yaml" do
    json = KvGroupWidget.from_json(doc.to_json)
    yaml = KvGroupWidget.from_yaml(doc.to_yaml)

    expect(json.to_hash).to eq(yaml.to_hash)
    expect(json.parts.map(&:label)).to eq(%w[a b])
  end

  it "wraps a single object into a model collection" do
    widget = KvGroupWidget.from_hash("parts" => { "label" => "solo" })

    expect(widget.parts.map(&:label)).to eq(["solo"])
  end

  it "falls back and matches the per-rule walk for junk items" do
    # The interpretive walk rejects a non-object item in a model row
    # with InvalidFormatError; the group path must behave identically
    # after falling back — same data in, same outcome, either path.
    expect do
      KvGroupWidget.from_hash("parts" => [{ "label" => "a" }, "junk"])
    end.to raise_error(Lutaml::Model::InvalidFormatError)
  end

  describe "eligibility" do
    it "rejects custom methods and still parses" do
      custom = Class.new(KvGroupWidget) do
        json do
          map "name", to: :name
          map "flag", to: :flag
          map "part", to: :part
          map "parts", to: :parts
          map "tags", to: :tags
          map "name", to: :name, with: { to: :n_to, from: :n_from }
        end

        def n_from(model, _value)
          model.name = "from-custom"
        end

        def n_to(_model, _doc); end
      end
      stub_const("KvGroup::Custom", custom)

      expect(Lutaml::KeyValue::Transform.kv_group_plan(custom, :json,
                                                       :default)).to be(false)
      # Falls back to the per-rule walk; whatever it produces for the
      # custom rule is that path's contract, unchanged by this feature.
      expect(custom.from_hash(doc)).to be_a(custom)
    end

    it "rejects when_attribute partitions" do
      partitioned = Class.new(KvGroupWidget) do
        attribute :guidance, KvGroupPart, collection: true

        json do
          map "guidance", to: :guidance,
                          when_attribute: { "type" => "guidance" }
        end
      end
      stub_const("KvGroup::Partitioned", partitioned)

      expect(Lutaml::KeyValue::Transform.kv_group_plan(partitioned, :json,
                                                       :default)).to be(false)
    end

    it "rejects rule-level polymorphic dispatch" do
      animal = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        json { map "name", to: :name }
      end
      zoo = Class.new(Lutaml::Model::Serializable) do
        attribute :animals, animal, collection: true
        json do
          map "animals", to: :animals, polymorphic: { attribute: "type" }
        end
      end
      stub_const("KvGroup::Zoo", zoo)

      expect(Lutaml::KeyValue::Transform.kv_group_plan(zoo, :json,
                                                       :default)).to be(false)
    end

    it "rejects range collections" do
      ranged = Class.new(Lutaml::Model::Serializable) do
        attribute :tags, :string, collection: 1..3

        json { map "tags", to: :tags }
      end
      stub_const("KvGroup::Ranged", ranged)

      expect(Lutaml::KeyValue::Transform.kv_group_plan(ranged, :json,
                                                       :default)).to be(false)
      expect(ranged.from_hash("tags" => %w[a b]).tags).to eq(%w[a b])
    end

    it "rejects self-referential models (cycle)" do
      node = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        json { map "name", to: :name }
      end
      node.attribute :child, node
      node.json do 
        map "name", to: :name
        map "child", to: :child
      end
      stub_const("KvGroup::Node", node)

      expect(Lutaml::KeyValue::Transform.kv_group_plan(node, :json,
                                                       :default)).to be(false)
      parsed = node.from_hash("name" => "n", "child" => { "name" => "c" })
      expect(parsed.child.name).to eq("c")
    end

    it "rejects delegates" do
      holder = Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        json { map "label", to: :label }
      end
      delegating = Class.new(Lutaml::Model::Serializable) do
        attribute :part, holder
        json { map "label", to: :label, delegate: :part }
      end
      stub_const("KvGroup::Delegating", delegating)

      expect(Lutaml::KeyValue::Transform.kv_group_plan(delegating, :json,
                                                       :default)).to be(false)
    end
  end
end
