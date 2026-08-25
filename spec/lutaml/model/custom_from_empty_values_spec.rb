# frozen_string: true

require "spec_helper"

# lutaml-model#746: an empty value ("", [], {}) is a PRESENT value per
# docs/_guides/missing-values-handling.adoc and must reach custom `from`
# methods. Only nil (non-existent) and an omitted key (undefined) skip them.
module CustomFromEmptyValuesSpec
  class Tagged < Lutaml::Model::Serializable
    attribute :received, :string

    key_value do
      map "tags", to: :received, with: { to: :tags_to, from: :tags_from }
    end

    def tags_to(model, doc)
      doc["tags"] = model.received
    end

    def tags_from(model, value)
      model.received = value.inspect
    end
  end

  class Mapped < Lutaml::Model::Serializable
    attribute :received, :string

    key_value do
      map "fields", to: :received, with: { to: :fields_to, from: :fields_from }
    end

    def fields_to(model, doc)
      doc["fields"] = model.received
    end

    def fields_from(model, value)
      model.received = value.inspect
    end
  end
end

RSpec.describe "custom from methods and empty values" do
  it "receives an empty collection" do
    expect(CustomFromEmptyValuesSpec::Tagged.from_yaml("tags: []").received)
      .to eq("[]")
  end

  it "receives an empty string" do
    expect(CustomFromEmptyValuesSpec::Tagged.from_yaml('tags: ""').received)
      .to eq("\"\"")
  end

  it "receives an empty mapping" do
    expect(CustomFromEmptyValuesSpec::Mapped.from_yaml("fields: {}").received)
      .to eq("{}")
  end

  it "receives empty values from JSON too" do
    expect(CustomFromEmptyValuesSpec::Tagged.from_json(%({"tags": []})).received)
      .to eq("[]")
    expect(CustomFromEmptyValuesSpec::Tagged.from_json(%({"tags": ""})).received)
      .to eq("\"\"")
  end

  it "still skips the method for a nil value" do
    expect(CustomFromEmptyValuesSpec::Tagged.from_yaml("tags:").received)
      .to be_nil
  end

  it "still skips the method for an omitted key" do
    expect(CustomFromEmptyValuesSpec::Tagged.from_yaml("{}").received)
      .to be_nil
  end
end
