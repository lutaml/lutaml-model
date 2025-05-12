# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema"

module DefinitionsCollectionSpec
  class Address < Lutaml::Model::Serializable
    attribute :street, Lutaml::Model::Type::String
  end

  class HomeAddress < Address
    attribute :is_home, Lutaml::Model::Type::Boolean
  end

  class WorkAddress < Address
    attribute :company, Lutaml::Model::Type::String
  end

  class Person < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String
    attribute :age, Lutaml::Model::Type::Integer
    attribute :address, Address, polymorphic: [HomeAddress, WorkAddress]
  end
end

RSpec.describe Lutaml::Model::Schema::Generator::DefinitionsCollection do
  let(:klass) { DefinitionsCollectionSpec::Person }

  describe ".from_class" do
    subject(:collection) { described_class.from_class(klass) }

    let(:all_classes) do
      [
        klass,
        DefinitionsCollectionSpec::Address,
        DefinitionsCollectionSpec::HomeAddress,
        DefinitionsCollectionSpec::WorkAddress,
      ]
    end

    it "creates a new DefinitionsCollection" do
      expect(collection).to be_a(described_class)
    end

    it "generated definition" do
      definition_class = Lutaml::Model::Schema::Generator::Definition
      expect(collection.definitions.first).to be_a(definition_class)
    end

    it "initializes with the main class definition" do
      expect(collection.definitions.size).to eq(all_classes.size)
    end

    it "includes definitions for main class and and all custom classes" do
      definition_types = collection.definitions.map(&:type)
      expect(definition_types).to include(*all_classes)
    end
  end

  describe "#to_schema" do
    subject(:schema) { collection.to_schema }

    let(:collection) { described_class.from_class(klass) }

    it "returns a hash" do
      expect(schema).to be_a(Hash)
    end

    it "includes schema for all definitions" do
      expect(schema.keys.size).to eq(collection.definitions.size)
    end
  end

  describe "#add_definition" do
    let(:collection) { described_class.new }
    let(:definition) do
      Lutaml::Model::Schema::Generator::Definition.new(String)
    end

    it "adds a definition to the collection" do
      expect { collection.add_definition(definition) }
        .to change { collection.definitions.size }.by(1)
    end

    it "accepts both Definition objects and classes" do
      expect { collection.add_definition(String) }
        .to change { collection.definitions.size }.by(1)
    end
  end

  describe "#merge" do
    let(:first_collection) do
      described_class.new(
        [
          Lutaml::Model::Type::String,
          Lutaml::Model::Type::Integer,
        ],
      )
    end
    let(:second_collection) do
      described_class.new(
        [
          Lutaml::Model::Type::Float,
          Lutaml::Model::Type::Boolean,
        ],
      )
    end

    it "merges two collections" do
      first_collection.merge(second_collection)
      expect(first_collection.definitions.size).to eq(4)
    end
  end
end
