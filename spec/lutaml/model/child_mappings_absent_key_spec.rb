# frozen_string_literal: true

require "spec_helper"

# A child_mappings rule whose wire key is absent crashed translate_mappings
# with an internal NoMethodError (nil.map) wrapped as InvalidFormatError.
# An absent key means the attribute keeps its uninitialized/default state,
# exactly like every other rule kind.
RSpec.describe "child_mappings rule with an absent key" do
  let(:schema_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :path, :string
    end
  end

  let(:model_class) do
    schemas = schema_class
    Class.new(Lutaml::Model::Serializable) do
      attribute :type, :string
      attribute :schemas, schemas, collection: true

      key_value do
        map "type", to: :type
        map "schemas", to: :schemas,
                       child_mappings: {
                         id: :key,
                         path: %i[path link],
                       }
      end
    end
  end

  before { stub_const("ChildMapAbsentModel", model_class) }

  it "parses without the key, leaving the attribute unset" do
    model = ChildMapAbsentModel.from_json('{"type":"object"}')

    expect(model.type).to eq("object")
    expect(model.schemas).to be_nil
  end

  it "still translates when the key is present" do
    model = ChildMapAbsentModel.from_json(
      '{"type":"object","schemas":{' \
      '"sch1":{"path":{"link":"https://example.com"}}}}',
    )

    expect(model.schemas.size).to eq(1)
    expect(model.schemas.first.id).to eq("sch1")
    expect(model.schemas.first.path).to eq("https://example.com")
  end
end
