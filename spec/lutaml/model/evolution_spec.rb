# frozen_string_literal: true

require "spec_helper"

# #265: model evolution — version metadata, wire-level migration steps
# between model versions, and family version detection. The migration
# steps operate on the source document's wire hash (deep-copied); the
# evolved hash parses as the target model through the hash format.
RSpec.describe "model evolution" do
  let(:v1_class) do
    Class.new(Lutaml::Model::Serializable) do
      version 1

      attribute :author, :string
      attribute :name, :string
      attribute :first_name, :string
      attribute :last_name, :string
      attribute :tag, :string
      attribute :deprecated_field, :string

      key_value do
        map "author", to: :author
        map "name", to: :name
        map "first_name", to: :first_name
        map "last_name", to: :last_name
        map "tag", to: :tag
        map "deprecated_field", to: :deprecated_field
      end
    end
  end

  let(:v2_class) do
    v1 = v1_class
    Class.new(v1) do
      version 2

      attribute :creator, :string
      attribute :full_name, :string
      attribute :tags, :string, collection: true
      attribute :metadata_name, :string

      key_value do
        map "creator", to: :creator
        map "full_name", to: :full_name
        map "tags", to: :tags
        map "metadata", to: :metadata_name,
                        child_mappings: { metadata_name: :name }
        map "deprecated_field", to: :deprecated_field, serialize: false
      end

      evolution from: v1 do
        wire_rename "author", to: "creator"
        wire_rename "tag", to: "tags"
        wire_merge %w[first_name last_name], to: "full_name",
                                             with: ->(first, last) { [first, last].compact.join(" ") }
        wire_drop "first_name", "last_name", "deprecated_field"
      end
    end
  end

  before do
    stub_const("EvolutionDocV1", v1_class)
    stub_const("EvolutionDocV2", v2_class)
  end

  it "stamps and inherits the model version" do
    expect(EvolutionDocV1.model_version).to eq(1)
    expect(EvolutionDocV2.model_version).to eq(2)
  end

  it "migrates a v1 hash into a v2 model through declared steps" do
    v2 = EvolutionDocV2.evolve(
      { "author" => "Ruth", "first_name" => "Ada", "last_name" => "L" },
      from: EvolutionDocV1,
    )

    expect(v2).to be_a(EvolutionDocV2)
    expect(v2.creator).to eq("Ruth")
    expect(v2.full_name).to eq("Ada L")
  end

  it "migrates a v1 instance through its own wire hash" do
    old = EvolutionDocV1.from_json(
      '{"author":"Ruth","tag":"core","deprecated_field":"gone"}',
    )
    v2 = EvolutionDocV2.evolve(old, from: EvolutionDocV1)

    expect(v2.creator).to eq("Ruth")
    expect(v2.tags).to eq(["core"])
  end

  it "does not mutate the caller's source hash" do
    source = { "author" => "Ruth", "first_name" => "Ada" }
    EvolutionDocV2.evolve(source, from: EvolutionDocV1)

    expect(source).to eq("author" => "Ruth", "first_name" => "Ada")
  end

  it "relocates keys with wire_move" do
    mover = Class.new(EvolutionDocV1) do
      version 3
      attribute :meta, :hash

      key_value do
        map "meta", to: :meta
      end

      evolution from: EvolutionDocV2 do
        wire_move "creator", to: "meta.creator"
      end
    end
    stub_const("EvolutionDocV3", mover)

    v3 = mover.evolve(
      { "creator" => "Ruth", "name" => "n" },
      from: EvolutionDocV2,
    )

    expect(v3.meta).to eq("creator" => "Ruth")
  end

  it "composes chains v1 -> v2 -> v3" do
    mover = Class.new(EvolutionDocV2) do
      version 3

      evolution from: EvolutionDocV2 do
        wire_drop "tag"
      end
    end
    stub_const("EvolutionDocV3Chain", mover)

    v3 = mover.evolve(
      { "author" => "Ruth", "first_name" => "Ada", "tag" => "x" },
      from: EvolutionDocV1,
    )

    expect(v3).to be_a(EvolutionDocV3Chain)
    expect(v3.creator).to eq("Ruth")
  end

  it "raises when no evolution path is declared" do
    unrelated = Class.new(Lutaml::Model::Serializable) do
      version 9
      attribute :x, :string
      key_value { map "x", to: :x }
    end
    stub_const("EvolutionUnrelated", unrelated)

    expect do
      EvolutionUnrelated.evolve({ "x" => 1 }, from: EvolutionDocV1)
    end.to raise_error(
      ArgumentError,
      /no evolution path from EvolutionDocV1 to EvolutionUnrelated/,
    )
  end

  describe "version detection" do
    let(:detecting_class) do
      Class.new(v2_class) do
        detect_version do |doc|
          doc["schema_version"] || 1
        end
      end
    end

    before { stub_const("EvolutionDetecting", detecting_class) }

    it "routes an older document to its own version's model" do
      parsed = EvolutionDetecting.from_json(
        '{"schema_version":1,"author":"Ruth"}',
      )

      expect(parsed).to be_a(EvolutionDocV1)
      expect(parsed.author).to eq("Ruth")
    end

    it "parses a current document as itself" do
      parsed = EvolutionDetecting.from_json(
        '{"schema_version":2,"creator":"Ruth"}',
      )

      expect(parsed).to be_a(EvolutionDetecting)
      expect(parsed.creator).to eq("Ruth")
    end

    it "raises on a version no family member declares" do
      expect do
        EvolutionDetecting.from_json('{"schema_version":42}')
      end.to raise_error(
        Lutaml::Model::UnsupportedVersionError,
        /version 42/,
      )
    end
  end

  describe "models without evolution declarations" do
    it "parses unchanged" do
      model = v1_class.from_json('{"author":"Ruth"}')

      expect(model.author).to eq("Ruth")
      expect(v1_class.model_version).to eq(1)
    end
  end
end
