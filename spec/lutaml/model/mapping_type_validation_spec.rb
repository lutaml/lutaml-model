# frozen_string_literal: true

require "spec_helper"

# lutaml-model#296: a mapped rule whose attribute type can never accept
# the serialization shape fails at mapping definition, naming the
# attribute and the type, instead of surfacing mid-parse.
RSpec.describe "Mapping-time attribute type validation" do
  it "raises InvalidAttributeTypeError at definition for a non-castable type" do
    expect do
      Class.new(Lutaml::Model::Serializable) do
        attribute :ends, Object

        xml do
          element "doc"
          map_element "ends", to: :ends
        end
      end
    end.to raise_error(Lutaml::Model::InvalidAttributeTypeError) do |err|
      expect(err.message).to include("attribute `ends`")
      expect(err.message).to include("Object")
    end
  end

  it "accepts Value, Serializable, and collection types" do
    item = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      xml do 
        element "item"
        map_element "name", to: :name
      end
    end

    expect do
      Class.new(Lutaml::Model::Serializable) do
        attribute :count, :integer
        attribute :name, :string
        attribute :items, item, collection: true

        xml do
          element "doc"
          map_element "count", to: :count
          map_element "items", to: :items
        end
      end
    end.not_to raise_error
  end

  it "leaves undeclared (deferred) types to import resolution" do
    expect do
      Class.new(Lutaml::Model::Serializable) do
        attribute :later, :missing_type_name

        xml do
          element "doc"
          map_element "later", to: :later
        end
      end
    end.not_to raise_error
  end
end
