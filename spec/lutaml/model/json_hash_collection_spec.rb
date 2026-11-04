# frozen_string_literal: true

require "spec_helper"

# lutaml-model#1114: a hash-valued entry in a string-collection
# attribute materialized as a Type::String wrapper holding the JSON
# text (data loss). Builtin scalars now keep structured data verbatim
# on parse and emit it verbatim on serialize; custom Value subclasses
# keep the wrapper/shaping contract.
module JsonHashCollectionSpec
  class Probe < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :files, :string, collection: true

    key_value do
      map "name", to: :name
      map "files", to: :files
    end
  end
end

RSpec.describe "hash-valued entries on string collections (#1114)" do
  let(:data) do
    { "name" => "Roboto", "files" => { "regular" => "Roboto-Regular.ttf" } }
  end

  it "keeps the hash structure on parse" do
    model = JsonHashCollectionSpec::Probe.from_json(JSON.dump(data))
    expect(model.files).to eq([{ "regular" => "Roboto-Regular.ttf" }])
  end

  it "round-trips the hash through to_json" do
    model = JsonHashCollectionSpec::Probe.from_json(JSON.dump(data))
    expect(JSON.parse(model.to_json)["files"])
      .to eq([{ "regular" => "Roboto-Regular.ttf" }])
  end
end
