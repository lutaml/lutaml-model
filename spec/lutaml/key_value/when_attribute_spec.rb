# frozen_string_literal: true

require "spec_helper"

# lutaml-model#88: `when_attribute` partitioning for key-value formats.
# The discriminator is an object key: items of the array at a shared wire
# key are claimed by the rule whose pairs their key values satisfy.
# Serialization merges every rule's items back under the one key, each
# item stamped with its rule's discriminator pairs.
class KvWhenComponent < Lutaml::Model::Serializable
  attribute :text, :string

  json do
    map "text", to: :text
  end

  yaml do
    map "text", to: :text
  end

  toml do
    map "text", to: :text
  end

  hsh do
    map "text", to: :text
  end
end

class KvWhenRequirement < Lutaml::Model::Serializable
  attribute :guidance, KvWhenComponent, collection: true
  attribute :purpose, KvWhenComponent, collection: true

  json do
    map "component", to: :guidance,
                     when_attribute: { "type" => "guidance" }
    map "component", to: :purpose,
                     when_attribute: { "type" => "purpose" }
  end

  yaml do
    map "component", to: :guidance,
                     when_attribute: { "type" => "guidance" }
    map "component", to: :purpose,
                     when_attribute: { "type" => "purpose" }
  end

  hsh do
    map "component", to: :guidance,
                     when_attribute: { "type" => "guidance" }
    map "component", to: :purpose,
                     when_attribute: { "type" => "purpose" }
  end
end

RSpec.describe "when_attribute for key-value formats" do
  before do
    stub_const("KvWhen::Component", KvWhenComponent)
    stub_const("KvWhen::Requirement", KvWhenRequirement)
  end

  let(:payload) do
    {
      "component" => [
        { "type" => "guidance", "text" => "g1" },
        { "type" => "purpose", "text" => "p1" },
        { "type" => "guidance", "text" => "g2" },
      ],
    }
  end

  it "partitions json by the discriminator key" do
    req = KvWhenRequirement.from_json(payload.to_json)

    expect(req.guidance.map(&:text)).to eq(%w[g1 g2])
    expect(req.purpose.map(&:text)).to eq(["p1"])
  end

  it "partitions yaml arrays of mappings" do
    req = KvWhenRequirement.from_yaml(payload.to_yaml)

    expect(req.guidance.map(&:text)).to eq(%w[g1 g2])
    expect(req.purpose.map(&:text)).to eq(["p1"])
  end

  it "partitions hashes passed directly with symbol keys" do
    req = KvWhenRequirement.from_hash(
      component: [
        { type: "guidance", text: "g1" },
        { type: "purpose", text: "p1" },
      ],
    )

    expect(req.guidance.map(&:text)).to eq(["g1"])
    expect(req.purpose.map(&:text)).to eq(["p1"])
  end

  it "keeps a single object occurrence as one item" do
    req = KvWhenRequirement.from_hash(
      "component" => { "type" => "purpose", "text" => "p1" },
    )

    expect(req.purpose.map(&:text)).to eq(["p1"])
    expect(req.guidance).to be_empty
  end

  it "serializes one merged array with the discriminators stamped" do
    req = KvWhenRequirement.from_json(payload.to_json)
    out = req.to_json

    items = JSON.parse(out)["component"]
    expect(items).to eq([
                          { "type" => "guidance", "text" => "g1" },
                          { "type" => "guidance", "text" => "g2" },
                          { "type" => "purpose", "text" => "p1" },
                        ])
  end

  it "round-trips through yaml" do
    req = KvWhenRequirement.from_yaml(payload.to_yaml)
    again = KvWhenRequirement.from_yaml(req.to_yaml)

    expect(again.guidance.map(&:text)).to eq(%w[g1 g2])
    expect(again.purpose.map(&:text)).to eq(["p1"])
  end

  it "does not stamp over a key the item's own mapping writes" do
    holder = Class.new(Lutaml::Model::Serializable) do
      attribute :items, KvWhenComponent, collection: true

      json do
        map "component", to: :items,
                         when_attribute: { "type" => "guidance" }
      end

      hsh do
        map "component", to: :items,
                         when_attribute: { "type" => "guidance" }
      end
    end
    stub_const("KvWhen::Holder", holder)

    out = holder.from_hash(
      "component" => [{ "type" => "guidance", "text" => "g" }],
    ).to_json
    expect(JSON.parse(out)["component"]).to eq(
      [{ "type" => "guidance", "text" => "g" }],
    )
  end

  describe "plain rule complement" do
    let(:holder) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :special, KvWhenComponent, collection: true
        attribute :plain, KvWhenComponent, collection: true

        json do
          map "item", to: :special, when_attribute: { "kind" => "special" }
          map "item", to: :plain
        end

        hsh do
          map "item", to: :special, when_attribute: { "kind" => "special" }
          map "item", to: :plain
        end
      end
    end

    it "captures occurrences no discriminator claimed exactly once" do
      stub_const("KvWhen::Both", holder)
      doc = holder.from_hash(
        "item" => [
          { "kind" => "special", "text" => "b" },
          { "text" => "a" },
          { "kind" => "other", "text" => "x" },
        ],
      )

      expect(doc.special.map(&:text)).to eq(["b"])
      expect(doc.plain.map(&:text)).to eq(%w[a x])
    end

    it "merges plain and stamped items into the one key" do
      stub_const("KvWhen::Both", holder)
      doc = holder.from_hash(
        "item" => [
          { "kind" => "special", "text" => "b" },
          { "text" => "a" },
        ],
      )
      items = JSON.parse(doc.to_json)["item"]

      expect(items).to eq([
                            { "kind" => "special", "text" => "b" },
                            { "text" => "a" },
                          ])
    end
  end

  describe "unmatched policy" do
    let(:strict) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :guidance, KvWhenComponent, collection: true

        json do
          map "component", to: :guidance,
                           when_attribute: { "type" => "guidance" },
                           unmatched: :raise
        end
      end
    end

    it "raises on an unclaimed discriminator value" do
      stub_const("KvWhen::Strict", strict)

      expect do
        strict.from_json({ "component" => [
          { "type" => "guidance", "text" => "g" },
          { "type" => "nope", "text" => "x" },
        ] }.to_json)
      end.to raise_error(Lutaml::Model::UnknownDiscriminatorError, /type="nope"/)
    end

    it "raises on an item without the discriminator key" do
      stub_const("KvWhen::Strict", strict)

      expect do
        strict.from_json({ "component" => [{ "text" => "x" }] }.to_json)
      end.to raise_error(Lutaml::Model::UnknownDiscriminatorError, /<component>/)
    end

    it "drops unclaimed occurrences by default" do
      lenient = Class.new(Lutaml::Model::Serializable) do
        attribute :guidance, KvWhenComponent, collection: true

        json do
          map "component", to: :guidance,
                           when_attribute: { "type" => "guidance" }
        end
      end
      stub_const("KvWhen::Lenient", lenient)

      doc = lenient.from_json({ "component" => [
        { "type" => "guidance", "text" => "g" },
        { "type" => "other", "text" => "x" },
      ] }.to_json)
      expect(doc.guidance.map(&:text)).to eq(["g"])
    end
  end

  describe "toml arrays of tables" do
    let(:toml_holder) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :guidance, KvWhenComponent, collection: true
        attribute :purpose, KvWhenComponent, collection: true

        toml do
          map "component", to: :guidance,
                           when_attribute: { "type" => "guidance" }
          map "component", to: :purpose,
                           when_attribute: { "type" => "purpose" }
        end
      end
    end

    it "partitions and round-trips" do
      stub_const("KvWhen::TomlHolder", toml_holder)
      src = <<~TOML
        [[component]]
        type = "guidance"
        text = "g1"

        [[component]]
        type = "purpose"
        text = "p1"
      TOML

      doc = toml_holder.from_toml(src)
      expect(doc.guidance.map(&:text)).to eq(["g1"])
      expect(doc.purpose.map(&:text)).to eq(["p1"])

      again = toml_holder.from_toml(doc.to_toml)
      expect(again.guidance.map(&:text)).to eq(["g1"])
      expect(again.purpose.map(&:text)).to eq(["p1"])
    end
  end

  describe "DSL validation" do
    it "rejects non-string/symbol pairs" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :x, :string

          json do
            map "x", to: :x, when_attribute: { "type" => 42 }
          end
        end
      end.to raise_error(Lutaml::Model::IncorrectMappingArgumentsError, /when_attribute/)
    end

    it "rejects unmatched without when_attribute" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :x, :string

          json do
            map "x", to: :x, unmatched: :raise
          end
        end
      end.to raise_error(Lutaml::Model::IncorrectMappingArgumentsError, /when_attribute/)
    end

    it "rejects unknown policy values" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :x, :string

          json do
            map "x", to: :x, when_attribute: { "type" => "a" },
                     unmatched: :explode
          end
        end
      end.to raise_error(Lutaml::Model::IncorrectMappingArgumentsError, /unmatched/)
    end

    it "rejects when_attribute combined with custom methods" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :x, :string

          json do
            map "x", to: :x, when_attribute: { "type" => "a" },
                     with: { to: :x_to, from: :x_from }
          end
        end
      end.to raise_error(Lutaml::Model::IncorrectMappingArgumentsError, /when_attribute/)
    end

    it "survives deep_dup of mappings" do
      rule = KvWhenRequirement.mappings_for(:json).mappings.find do |r|
        r.to == :guidance
      end

      expect(rule.when_attribute).to eq("type" => "guidance")
      expect(rule.deep_dup.when_attribute).to eq("type" => "guidance")
    end
  end
end
