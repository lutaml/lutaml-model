require "spec_helper"
require "lutaml/model"

module InheritanceSpec
  class Parent < Lutaml::Model::Serializable
    attribute :text, Lutaml::Model::Type::String
    attribute :id, Lutaml::Model::Type::String
    attribute :name, Lutaml::Model::Type::String

    xml do
      map_content to: :text

      map_attribute "id", to: :id
      map_element "name", to: :name
    end
  end

  class Child < Parent
    attribute :age, Lutaml::Model::Type::Integer

    xml do
      root "child"

      map_element "age", to: :age
    end
  end
end

RSpec.describe "Inheritance" do
  subject(:child_object) do
    InheritanceSpec::Child.new(
      {
        text: "Some text",
        name: "John Doe",
        id: "foobar",
        age: 30,
      },
    )
  end

  let(:expected_xml) do
    '<child id="foobar"><name>John Doe</name><age>30</age>Some text</child>'
  end

  it "uses parent attributes" do
    expect(child_object.to_xml(pretty: true)).to eq(expected_xml)
  end
end
