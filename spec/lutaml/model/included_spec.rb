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

  module ParentClass
    include Lutaml::Model::Serialize
    
    attribute :parent_name, Lutaml::Model::Type::String
    
    xml do
      root "parent"
      map_element "parent_name", to: :parent_name
    end
  end

  module ChildClass
    include ParentClass
    attribute :child_name, Lutaml::Model::Type::String
    
    xml do
      root "child"
      map_element "child_name", to: :child_name
    end
  end

  class GrandChildClass
    include ChildClass
    attribute :grandchild_name, Lutaml::Model::Type::String
    
    xml do
      root "grandchild"
      map_element "grandchild_name", to: :grandchild_name
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

  context "with nested module inclusion" do
    let(:grandchild) do
      IncludedSpec::GrandChildClass.new(
        parent_name: "Parent",
        child_name: "Child",
        grandchild_name: "GrandChild"
      )
    end
  
    it "inherits attributes through the chain" do
      expect(IncludedSpec::GrandChildClass.attributes.keys)
        .to include(:parent_name, :child_name, :grandchild_name)
    end
  
    it "maintains correct XML mappings through inheritance" do
      expect(grandchild.to_xml(pretty: true))
        .to include("<parent_name>Parent</parent_name>")
        .and include("<child_name>Child</child_name>")
        .and include("<grandchild_name>GrandChild</grandchild_name>")
    end
  
    it "preserves separate mapping configurations" do
      expect(IncludedSpec::ParentClass.mappings_for(:xml).root_element).to eq("parent")
      expect(IncludedSpec::ChildClass.mappings_for(:xml).root_element).to eq("child")
      expect(IncludedSpec::GrandChildClass.mappings_for(:xml).root_element).to eq("grandchild")
    end
  end
end
