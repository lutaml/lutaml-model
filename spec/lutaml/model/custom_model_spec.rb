require "spec_helper"

class CustomModelChild
  attr_accessor :street, :city
end

class CustomModelParent
  attr_accessor :first_name, :last_name, :child_mapper

  def name
    "#{first_name} #{last_name}"
  end
end

class CustomModelChildMapper < Lutaml::Model::Serializable
  model CustomModelChild

  attribute :street, Lutaml::Model::Type::String
  attribute :city, Lutaml::Model::Type::String

  xml do
    map_element :street, to: :street
    map_element :city, to: :city
  end
end

class CustomModelParentMapper < Lutaml::Model::Serializable
  model CustomModelParent

  attribute :first_name, Lutaml::Model::Type::String
  attribute :last_name, Lutaml::Model::Type::String
  attribute :child_mapper, CustomModelChildMapper

  xml do
    map_element :first_name, to: :first_name
    map_element :last_name, to: :last_name
    map_element :CustomModelChild, to: :child_mapper
  end
end

RSpec.describe "CustomModel" do
  let(:parent_mapper) { CustomModelParentMapper }
  let(:child_mapper) { CustomModelChildMapper }
  let(:parent_model) { CustomModelParent }
  let(:child_model) { CustomModelChild }

  context "with JSON mapping" do
    let(:input_json) do
      {
        first_name: "John",
        last_name: "Doe",
        child_mapper: {
          street: "Oxford Street",
          city: "London",
        },
      }.to_json
    end

    describe ".from_json" do
      it "maps JSON string to custom model" do
        instance = parent_mapper.from_json(input_json)

        expect(instance.class).to eq(parent_model)
        expect(instance.first_name).to eq("John")
        expect(instance.last_name).to eq("Doe")
        expect(instance.name).to eq("John Doe")

        expect(instance.child_mapper.class).to eq(child_model)
        expect(instance.child_mapper.street).to eq("Oxford Street")
        expect(instance.child_mapper.city).to eq("London")
      end
    end

    describe ".to_json" do
      it "with wrong model raises an exception" do
        msg = /argument is a 'String' but should be a '#{parent_model.name}/

        expect do
          parent_mapper.to_json("")
        end.to raise_error(Lutaml::Model::IncorrectModelError, msg)
      end

      it "with correct model converts objects to json" do
        instance = parent_mapper.from_json(input_json)

        expect(parent_mapper.to_json(instance)).to eq(input_json)
      end
    end
  end

  context "with YAML mapping" do
    let(:input_yaml) do
      {
        "first_name" => "John",
        "last_name" => "Doe",
        "child_mapper" => {
          "street" => "Oxford Street",
          "city" => "London",
        },
      }.to_yaml
    end

    describe ".from_yaml" do
      it "maps YAML to custom model" do
        instance = parent_mapper.from_yaml(input_yaml)

        expect(instance.class).to eq(parent_model)
        expect(instance.first_name).to eq("John")
        expect(instance.last_name).to eq("Doe")
        expect(instance.name).to eq("John Doe")

        expect(instance.child_mapper.class).to eq(child_model)
        expect(instance.child_mapper.street).to eq("Oxford Street")
        expect(instance.child_mapper.city).to eq("London")
      end
    end

    describe ".to_yaml" do
      it "with wrong model raises an exception" do
        msg = /argument is a 'String' but should be a '#{parent_model.name}/

        expect do
          parent_mapper.to_yaml("")
        end.to raise_error(Lutaml::Model::IncorrectModelError, msg)
      end

      it "with correct model converts objects to yaml" do
        instance = parent_mapper.from_yaml(input_yaml)

        expect(parent_mapper.to_yaml(instance)).to eq(input_yaml)
      end
    end
  end

  context "with TOML mapping" do
    let(:input_toml) do
      <<~TOML
        first_name = "John"
        last_name = "Doe"
        [child_mapper]
        city = "London"
        street = "Oxford Street"
      TOML
    end

    describe ".from_toml" do
      it "maps TOML content to custom model" do
        instance = parent_mapper.from_toml(input_toml)

        expect(instance.class).to eq(parent_model)
        expect(instance.first_name).to eq("John")
        expect(instance.last_name).to eq("Doe")
        expect(instance.name).to eq("John Doe")

        expect(instance.child_mapper.class).to eq(child_model)
        expect(instance.child_mapper.street).to eq("Oxford Street")
        expect(instance.child_mapper.city).to eq("London")
      end
    end

    describe ".to_toml" do
      it "with wrong model raises an exception" do
        msg = /argument is a 'String' but should be a '#{parent_model.name}/

        expect do
          parent_mapper.to_toml("")
        end.to raise_error(Lutaml::Model::IncorrectModelError, msg)
      end

      it "with correct model converts objects to toml" do
        instance = parent_mapper.from_toml(input_toml)

        expect(parent_mapper.to_toml(instance)).to eq(input_toml)
      end
    end
  end

  context "with XML mapping" do
    let(:input_xml) do
      <<~XML
        <CustomModelParent>
          <first_name>John</first_name>
          <last_name>Doe</last_name>
          <CustomModelChild>
            <street>Oxford Street</street>
            <city>London</city>
          </CustomModelChild>
        </CustomModelParent>
      XML
    end

    describe ".from_xml" do
      it "maps XML content to custom model" do
        instance = parent_mapper.from_xml(input_xml)

        expect(instance.class).to eq(parent_model)
        expect(instance.first_name).to eq("John")
        expect(instance.last_name).to eq("Doe")
        expect(instance.name).to eq("John Doe")

        expect(instance.child_mapper.class).to eq(child_model)
        expect(instance.child_mapper.street).to eq("Oxford Street")
        expect(instance.child_mapper.city).to eq("London")
      end
    end

    describe ".to_xml" do
      it "with wrong model raises an exception" do
        msg = /argument is a 'String' but should be a '#{parent_model.name}/

        expect do
          parent_mapper.to_xml("")
        end.to raise_error(Lutaml::Model::IncorrectModelError, msg)
      end

      it "with correct model converts objects to xml" do
        instance = parent_mapper.from_xml(input_xml)

        expect(parent_mapper.to_xml(instance).strip).to eq(input_xml.strip)
      end
    end
  end
end
