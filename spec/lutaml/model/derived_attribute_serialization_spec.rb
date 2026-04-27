# frozen_string_literal: true

require "spec_helper"

module DerivedAttributeSerializationSpec
  class Parent < Lutaml::Model::Serializable
    attribute :computed_val, :string, method: :computed_value

    xml do
      root "parent"
      map_attribute "computed-val", to: :computed_val, render_default: true
    end

    def computed_value
      "hello"
    end
  end
end

RSpec.describe "derived attribute serialization after XML deserialization" do
  it "keeps derived attributes in YAML output after XML deserialization" do
    instance = DerivedAttributeSerializationSpec::Parent.from_xml("<parent/>")

    expect(instance.computed_val).to eq("hello")
    expect(instance.to_yaml).to include("computed_val: hello")
  end

  it "keeps derived attributes in key-value output after XML deserialization" do
    instance = DerivedAttributeSerializationSpec::Parent.from_xml("<parent/>")

    expect(instance.to_json).to include("\"computed_val\":\"hello\"")
  end
end
