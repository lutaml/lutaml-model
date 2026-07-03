require "spec_helper"
require_relative "../../../lib/lutaml/model"

module CardinalityStrictSpec
  class Person < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :nick, :string, collection: 0..2

    xml do
      root "person"
      map_element "name", to: :name
      map_element "nick", to: :nick
    end

    json do
      map "name", to: :name
      map "nick", to: :nick
    end
  end
end

RSpec.describe "Issue #185 strict cardinality" do
  describe "XML non-collection map_element over-count" do
    it "raises at parse, consistent with key/value" do
      expect do
        CardinalityStrictSpec::Person.from_xml(
          "<person><name>A</name><name>B</name></person>",
        )
      end.to raise_error(Lutaml::Model::CollectionTrueMissingError, /`name`/)
    end

    it "accepts a single occurrence as a scalar" do
      obj = CardinalityStrictSpec::Person.from_xml(
        "<person><name>A</name></person>",
      )
      expect(obj.name).to eq("A")
    end

    it "accepts zero occurrences" do
      obj = CardinalityStrictSpec::Person.from_xml("<person/>")
      expect(obj.name).to be_nil
    end
  end

  describe "key/value non-collection over-count (existing behavior, unchanged)" do
    it "raises at parse" do
      expect do
        CardinalityStrictSpec::Person.from_json('{"name":["A","B"]}')
      end.to raise_error(Lutaml::Model::CollectionTrueMissingError)
    end
  end

  describe "declared collection range stays lazy (unchanged)" do
    it "does not raise at parse for XML over-max; flags on validate" do
      obj = nil
      expect do
        obj = CardinalityStrictSpec::Person.from_xml(
          "<person><nick>a</nick><nick>b</nick><nick>c</nick></person>",
        )
      end.not_to raise_error
      expect(obj.validate).to include(
        an_instance_of(Lutaml::Model::CollectionCountOutOfRangeError),
      )
    end

    it "accepts XML within range" do
      obj = CardinalityStrictSpec::Person.from_xml(
        "<person><nick>a</nick><nick>b</nick></person>",
      )
      expect(obj.validate).to be_empty
    end
  end

  describe "map_content stays lazy (unchanged)" do
    let(:mixed) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name = "CardinalityStrictSpec::Mixed"
        attribute :bold, :string, collection: true
        attribute :content, :string
        xml do
          root "r"
          map_element "bold", to: :bold
          map_content to: :content
        end
      end
    end

    it "does not raise at parse; flags a singular content target on validate" do
      obj = nil
      expect do
        obj = mixed.from_xml(
          "<r>one <bold>b</bold> two <bold>c</bold> three</r>",
        )
      end.not_to raise_error
      expect(obj.validate).to include(
        an_instance_of(Lutaml::Model::CollectionTrueMissingError),
      )
    end
  end
end
