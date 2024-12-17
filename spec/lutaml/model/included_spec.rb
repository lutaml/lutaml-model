require "spec_helper"
require "lutaml/model"

module IncludedSpec
  class Base
    include Lutaml::Model::Serialize

    attribute :text, Lutaml::Model::Type::String
    attribute :id, Lutaml::Model::Type::String
    attribute :name, Lutaml::Model::Type::String

    xml do
      map_content to: :text
      map_attribute "id", to: :id
      map_element "name", to: :name
    end
  end

  class Implementation1
    include Lutaml::Model::Serialize

    attribute :text, Lutaml::Model::Type::String
    attribute :id, Lutaml::Model::Type::String
    attribute :name, Lutaml::Model::Type::String
    attribute :age, Lutaml::Model::Type::Integer

    xml do
      root "impl_one"
      map_content to: :text
      map_attribute "id", to: :id
      map_element "name", to: :name
      map_element "age", to: :age
    end
  end

  class Implementation2
    include Lutaml::Model::Serialize

    attribute :text, Lutaml::Model::Type::String
    attribute :id, Lutaml::Model::Type::String
    attribute :name, Lutaml::Model::Type::String
    attribute :age, Lutaml::Model::Type::Integer

    xml do
      root "impl_two"
      map_content to: :text
      map_attribute "id", to: :id
      map_element "name", to: :name
      map_element "gender", to: :age
    end
  end
end

RSpec.describe "Module Inclusion" do
  subject(:impl_object) do
    IncludedSpec::Implementation1.new(
      {
        text: "Some text",
        name: "John Doe",
        id: "foobar",
        age: 30,
      },
    )
  end

  let(:expected_xml) do
    '<impl_one id="foobar"><name>John Doe</name><age>30</age>Some text</impl_one>'
  end

  it "uses included module attributes" do
    expect(impl_object.to_xml(pretty: true)).to eq(expected_xml)
  end

  context "with multiple implementing classes" do
    describe "Implementation1" do
      let(:impl1) { IncludedSpec::Implementation1 }

      it "has correct mappings" do
        expect(impl1.mappings_for(:xml).mappings.count).to eq(4)
      end

      it "has correct attributes" do
        expect(impl1.attributes.count).to eq(4)
      end

      it "has correct model" do
        expect(impl1.model).to eq(impl1)
      end
    end

    describe "Implementation2" do
      let(:impl2) { IncludedSpec::Implementation2 }

      it "has correct mappings" do
        expect(impl2.mappings_for(:xml).mappings.count).to eq(4)
      end

      it "has correct attributes" do
        expect(impl2.attributes.count).to eq(4)
      end

      it "has correct model" do
        expect(impl2.model).to eq(impl2)
      end
    end
  end
end
