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

  class Child1 < Parent
    attribute :age, Lutaml::Model::Type::Integer

    xml do
      root "child"

      map_element "age", to: :age
    end
  end

  class Child2 < Parent
    attribute :age, Lutaml::Model::Type::Integer

    xml do
      root "child_two"

      map_element "gender", to: :age
    end
  end

  class ParentWithMapAll < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :description, :string

    xml do
      map_attribute "id", to: :id
      map_all_content to: :description
    end
  end

  class Child < ParentWithMapAll
    xml do
      root "child"
    end
  end

  class Reference < Lutaml::Model::Serializable
  end

  class FirstRefMapper < Reference
    attribute :name, :string
    attribute :id, :string

    key_value do
      map "name", to: :name
      map "id", to: :id
    end
  end

  class SecondRefMapper < Reference
    attribute :name, :string
    attribute :desc, :string

    key_value do
      map "name", to: :name
      map "desc", to: :desc
    end
  end

  class FirstRef
    attr_accessor :name, :id

    def initialize(id:, name:)
      @id = id
      @name = name
    end
  end

  class SecondRef
    attr_accessor :name, :desc

    def initialize(desc:, name:)
      @desc = desc
      @name = name
    end
  end

  class FirstRefMapperWithCustomModel < Reference
    model FirstRef

    attribute :name, :string
    attribute :id, :string

    key_value do
      map "name", to: :name
      map "id", to: :id
    end
  end

  class SecondRefMapperWithCustomModel < Reference
    model SecondRef

    attribute :name, :string
    attribute :desc, :string

    key_value do
      map "name", to: :name
      map "desc", to: :desc
    end
  end
end

RSpec.describe "Inheritance" do
  subject(:child_object) do
    InheritanceSpec::Child1.new(
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
    expect(child_object.to_xml(pretty: true)).to be_equivalent_to(expected_xml)
  end

  context "with multiple child classes" do
    describe "Child1" do
      let(:child1) { InheritanceSpec::Child1 }

      it "has correct mappings" do
        expect(child1.mappings_for(:xml).mappings.count).to eq(4)
      end

      it "has correct attributes" do
        expect(child1.attributes.count).to eq(4)
      end

      it "has correct model" do
        expect(child1.model).to eq(child1)
      end
    end

    describe "Child2" do
      let(:child2) { InheritanceSpec::Child2 }

      it "has correct mappings" do
        expect(child2.mappings_for(:xml).mappings.count).to eq(4)
      end

      it "has correct attributes" do
        expect(child2.attributes.count).to eq(4)
      end

      it "has correct model" do
        expect(child2.model).to eq(child2)
      end
    end
  end

  context "with map_all in parent" do
    let(:xml) { "<child id=\"en\">Some <b>bold</b> Content</child>" }

    it "round trip correctly" do
      parsed = InheritanceSpec::Child.from_xml(xml)
      expect(parsed.to_xml).to be_equivalent_to(xml)
    end
  end

  context "when parent class is given in type" do
    before do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :klass, InheritanceSpec::Reference

        key_value do
          map "klass", to: :klass
        end
      end

      stub_const("TestClass", test_class)
    end

    context "without custom models" do
      let(:first_ref_mapper) do
        InheritanceSpec::FirstRefMapper.new(
          name: "first_mapper",
          id: "one",
        )
      end

      let(:first_ref_mapper_yaml) do
        <<~YAML
          ---
          klass:
            name: first_mapper
            id: one
        YAML
      end

      let(:second_ref_mapper) do
        InheritanceSpec::SecondRefMapper.new(
          name: "second_mapper",
          desc: "second mapper",
        )
      end

      let(:second_ref_mapper_yaml) do
        <<~YAML
          ---
          klass:
            name: second_mapper
            desc: second mapper
        YAML
      end

      it "outputs correct yaml for first_ref_mapper class" do
        expect(TestClass.new(klass: first_ref_mapper).to_yaml)
          .to eq(first_ref_mapper_yaml)
      end

      it "outputs correct yaml for second_ref_mapper class" do
        expect(TestClass.new(klass: second_ref_mapper).to_yaml)
          .to eq(second_ref_mapper_yaml)
      end
    end

    context "when not using custom models" do
      let(:first_ref) do
        InheritanceSpec::FirstRef.new(
          name: "first",
          id: "one",
        )
      end

      let(:second_ref) do
        InheritanceSpec::SecondRef.new(
          name: "second",
          desc: "second",
        )
      end

      it "outputs correct yaml for first_ref class" do
        expect { TestClass.new(klass: first_ref).to_yaml }
          .to raise_error(Lutaml::Model::IncorrectModelError)
      end

      it "outputs correct yaml for second_ref class" do
        expect { TestClass.new(klass: second_ref).to_yaml }
          .to raise_error(Lutaml::Model::IncorrectModelError)
      end
    end
  end
end
