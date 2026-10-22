# frozen_string_literal: true

require "spec_helper"

# #985: `map_unmapped to:` collects document keys no declared rule claims
# into the given attribute, so vendor extensions and forward-compatible
# keywords survive the round-trip. Opt-in: models without the directive
# keep the drop behavior. Compiled fast paths are ineligible for such
# models — the collect runs on the interpretive walk.
RSpec.describe "key-value catch-all mapping (map_unmapped)" do
  let(:schema_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :type, :string
      attribute :description, :string
      attribute :extensions, :hash, default: -> { {} }

      key_value do
        map "type", to: :type
        map "description", to: :description
        map_unmapped to: :extensions
      end
    end
  end

  let(:plain_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :type, :string

      key_value do
        map "type", to: :type
      end
    end
  end

  before do
    stub_const("MapUnmappedSchema", schema_class)
    stub_const("MapUnmappedPlain", plain_class)
  end

  it "collects unmapped keys on parse" do
    model = MapUnmappedSchema.from_json(
      '{"type":"object","x-enumDescriptions":{"a":"A"},"future":true}',
    )

    expect(model.type).to eq("object")
    expect(model.extensions).to eq(
      "x-enumDescriptions" => { "a" => "A" }, "future" => true,
    )
  end

  it "never duplicates keys claimed by a rule" do
    model = MapUnmappedSchema.from_json('{"type":"object"}')

    expect(model.extensions).to eq({})
  end

  it "re-emits collected keys verbatim on serialization" do
    model = MapUnmappedSchema.from_json(
      '{"type":"object","x-enumDescriptions":{"a":"A"},"future":true}',
    )
    out = JSON.parse(model.to_json)

    expect(out["x-enumDescriptions"]).to eq("a" => "A")
    expect(out["future"]).to be(true)
    expect(out["type"]).to eq("object")
  end

  it "lets mapped keys win on collision with collected keys" do
    model = MapUnmappedSchema.new
    model.type = "object"
    model.extensions = { "type" => "extension-wins-only-if-unmapped" }

    out = JSON.parse(model.to_json)

    expect(out["type"]).to eq("object")
  end

  it "round-trips in yaml through the same contract" do
    model = MapUnmappedSchema.from_yaml(
      <<~YAML,
        type: object
        x-vendor: kept
      YAML
    )

    expect(model.extensions).to eq("x-vendor" => "kept")
    expect(YAML.safe_load(model.to_yaml)["x-vendor"]).to eq("kept")
  end

  it "fails fast when the target is not a declared attribute" do
    typo_class = Class.new(Lutaml::Model::Serializable) do
      attribute :type, :string

      key_value do
        map "type", to: :type
        map_unmapped to: :extenshuns
      end
    end
    stub_const("MapUnmappedTypo", typo_class)

    # from_json wraps the raise in the format-error contract, message
    # intact; to_json surfaces the bare ArgumentError at compile.
    expect do
      typo_class.from_json('{"type":"object","x-a":1}')
    end.to raise_error(
      Lutaml::Model::InvalidFormatError,
      /map_unmapped target :extenshuns is not a declared attribute of/,
    )
    expect do
      typo_class.new.to_json
    end.to raise_error(
      ArgumentError,
      /map_unmapped target :extenshuns is not a declared attribute of/,
    )
  end

  it "keeps the drop behavior when no catch-all is declared" do
    model = MapUnmappedPlain.from_json('{"type":"object","x-lost":1}')

    expect(model.to_json).not_to include("x-lost")
  end

  it "collects per instance in nested models" do
    container = Class.new(Lutaml::Model::Serializable) do
      attribute :child, "MapUnmappedSchema"

      key_value do
        map "child", to: :child
      end
    end
    stub_const("MapUnmappedContainer", container)

    model = MapUnmappedContainer.from_json(
      '{"child":{"type":"object","x-inner":1}}',
    )

    expect(model.child.extensions).to eq("x-inner" => 1)
  end
end
