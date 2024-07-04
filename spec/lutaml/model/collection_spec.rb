# spec/lutaml/model/collection_spec.rb
require "spec_helper"
require "lutaml/model"

module CollectionTests
  class Pot < Lutaml::Model::Serializable
    attribute :material, Lutaml::Model::Type::String

    xml do
      root "pot"
      map_element "material", to: :material
    end
  end

  class Kiln < Lutaml::Model::Serializable
    attribute :brand, Lutaml::Model::Type::String
    attribute :pots, Pot, collection: true
    attribute :temperatures, Lutaml::Model::Type::Integer, collection: true

    xml do
      root "kiln"
      map_attribute "brand", to: :brand
      map_element "pot", to: :pots
      map_element "temperature", to: :temperatures
    end
  end
end

RSpec.describe CollectionTests do
  let(:pots) { [{ material: "clay" }, { material: "ceramic" }] }
  let(:temperatures) { [1200, 1300, 1400] }
  let(:attributes) { { brand: "Skutt", pots: pots, temperatures: temperatures } }
  let(:model) { CollectionTests::Kiln.new(attributes) }

  let(:model_xml) {
    <<~XML
      <kiln brand="Skutt">
        <pot>
          <material>clay</material>
        </pot>
        <pot>
          <material>ceramic</material>
        </pot>
        <temperature>1200</temperature>
        <temperature>1300</temperature>
        <temperature>1400</temperature>
      </kiln>
    XML
  }

  it "initializes with default values" do
    default_model = CollectionTests::Kiln.new
    expect(default_model.brand).to eq(nil)
    expect(default_model.pots).to eq([])
    expect(default_model.temperatures).to eq([])
  end

  it "serializes to XML" do
    expected_xml = model_xml.strip
    expect(model.to_xml.strip).to eq(expected_xml)
  end

  it "deserializes from XML" do
    sample = CollectionTests::Kiln.from_xml(model_xml)
    expect(sample.brand).to eq("Skutt")
    expect(sample.pots.size).to eq(2)
    expect(sample.pots[0].material).to eq("clay")
    expect(sample.pots[1].material).to eq("ceramic")
    expect(sample.temperatures).to eq([1200, 1300, 1400])
  end

  it "round-trips XML" do
    xml = model.to_xml
    new_model = CollectionTests::Kiln.from_xml(xml)
    expect(new_model.brand).to eq(model.brand)
    expect(new_model.pots.size).to eq(model.pots.size)
    model.pots.each_with_index do |pot, index|
      expect(new_model.pots[index].material).to eq(pot.material)
    end
    expect(new_model.temperatures).to eq(model.temperatures)
  end
end
