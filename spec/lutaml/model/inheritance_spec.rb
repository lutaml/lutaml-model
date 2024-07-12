# spec/lutaml/model/inheritance_spec.rb
require "spec_helper"
require "lutaml/model"

class Parent < Lutaml::Model::Serializable
  attribute :text, Lutaml::Model::Type::String
  attribute :id, Lutaml::Model::Type::String
  attribute :name, Lutaml::Model::Type::String
end

class Child < Parent
  attribute :age, Lutaml::Model::Type::Integer

  xml do
    root "child"

    map_content to: :text

    map_attribute "id", to: :id

    map_element "age", to: :age
    map_element "name", to: :name
  end
end

RSpec.describe Child do
  subject do
    described_class.new({
      text: "Some text",
      name: "John Doe",
      id: "foobar",
      age: 30,
    })
  end

  let(:expected_xml) do
    '<child id="foobar"><age>30</age><name>John Doe</name>Some text</child>'
  end

  it "should use parent attributes" do
    expect(subject.to_xml(pretty: true)).to eq(expected_xml)
  end
end
