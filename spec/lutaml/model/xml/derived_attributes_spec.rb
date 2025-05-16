# frozen_string_literal: true

require "spec_helper"

module DerivedAttributesSpecs
  class Ceramic < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :value, register(:float)
  end

  class CeramicCollection < Lutaml::Model::Serializable
    attribute :items, Ceramic, collection: true
    attribute :total_value, method: :total_value

    # Derived property
    def total_value
      items.sum(&:value)
    end

    xml do
      root "ceramic-collection"
      map_element "total-value", to: :total_value
      map_element "item", to: :items
    end
  end
end

RSpec.describe "XML::DerivedAttributes" do
  let(:xml) do
    <<~XML.strip
      <ceramic-collection>
        <total-value>2500.0</total-value>
        <item>
          <name>Ancient Vase</name>
          <value>1500.0</value>
        </item>
        <item>
          <name>Historic Bowl</name>
          <value>1000.0</value>
        </item>
      </ceramic-collection>
    XML
  end

  let(:ancient_vase) do
    DerivedAttributesSpecs::Ceramic.new(name: "Ancient Vase", value: 1500.0)
  end

  let(:historic_bowl) do
    DerivedAttributesSpecs::Ceramic.new(name: "Historic Bowl", value: 1000.0)
  end

  let(:ceramic_collection) do
    DerivedAttributesSpecs::CeramicCollection.new(
      items: [ancient_vase, historic_bowl],
    )
  end

  describe ".from_xml" do
    let(:parsed) do
      DerivedAttributesSpecs::CeramicCollection.from_xml(xml)
    end

    it "correctly parses items" do
      expect(parsed).to eq(ceramic_collection)
    end

    it "correctly calculates total-value" do
      expect(parsed.total_value).to eq(2500)
    end
  end

  describe ".to_xml" do
    it "convert to correct xml" do
      expect(ceramic_collection.to_xml).to eq(xml)
    end
  end
end
