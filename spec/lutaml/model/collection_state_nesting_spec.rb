# frozen_string_literal: true

require "spec_helper"

# A Collection overrides #to_format and merges `collection: true` into the
# options BEFORE the base implementation runs. JSON::State#merge is #configure,
# which rejects unknown keys on json 3.0, so the state has to be wrapped first.
RSpec.describe "a collection nested inside JSON.generate" do
  before do
    stub_const("NestedItem", Class.new(Lutaml::Model::Serializable) do
      attribute :n, :string
    end)
    stub_const("NestedItems", Class.new(Lutaml::Model::Collection) do
      instances :items, NestedItem
    end)
  end

  let(:collection) { NestedItems.new([NestedItem.new(n: "a")]) }

  it "serializes inside a Hash" do
    expect(JSON.generate({ "c" => collection })).to eq('{"c":[{"n":"a"}]}')
  end

  it "inherits the outer indent inside a pretty Hash" do
    expect(JSON.pretty_generate({ "c" => collection }))
      .to eq(%({\n  "c": [\n    {\n      "n": "a"\n    }\n  ]\n}))
  end

  # The class-level entry point normalises separately from the instance one,
  # and deleting that normaliser leaves every instance example green.
  it "normalises a state passed to the class-level entry point" do
    # array_nl is what puts the newlines in an array; without it the state
    # is not a pretty state at all and the example proves nothing.
    state = JSON::State.new(indent: "  ", object_nl: "\n", array_nl: "\n",
                            space: " ")

    expect(NestedItems.to_json(collection, state))
      .to eq(%([\n  {\n    "n": "a"\n  }\n]))
  end

  it "still serializes directly" do
    expect(collection.to_json).to eq('[{"n":"a"}]')
  end
end
