# frozen_string_literal: true

require "spec_helper"

# A Collection routed through the MultiJson adapter carries `collection: true`
# in its options. MultiJson forwards whatever it is given to the backend, and
# the json_gem backend is JSON.generate, which rejects it on json 3.0.
RSpec.describe "a collection serialized through the multi_json adapter" do
  before do
    require "multi_json"
    stub_const("MjItem", Class.new(Lutaml::Model::Serializable) do
      attribute :n, :string
    end)
    stub_const("MjItems", Class.new(Lutaml::Model::Collection) do
      instances :items, MjItem
    end)
  end

  it "does not leak LutaML's own options into the engine" do
    result = Lutaml::Model::Config.with_adapter(json: :multi_json) do
      MjItems.new([MjItem.new(n: "a")]).to_json
    end

    expect(result).to eq('[{"n":"a"}]')
  end
end
