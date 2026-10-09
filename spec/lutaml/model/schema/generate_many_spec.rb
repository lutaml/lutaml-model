# frozen_string_literal: true

require "spec_helper"

module GenerateManySpec
  class Source < Lutaml::Model::Serializable
    attribute :name, :string
  end

  class Other < Lutaml::Model::Serializable
    attribute :label, :string
  end

  class Consumer < Lutaml::Model::Serializable
    attribute :inner, Source
  end
end

RSpec.describe Lutaml::Model::Schema::BaseSchema do
  describe ".generate_many" do
    it "covers every root in one document without a top-level $ref" do
      parsed = JSON.parse(
        Lutaml::Model::Schema::JsonSchema.generate_many(
          [GenerateManySpec::Source, GenerateManySpec::Other],
        ),
      )

      expect(parsed).not_to have_key("$ref")
      expect(parsed["$defs"]).to have_key("GenerateManySpec_Source")
      expect(parsed["$defs"]).to have_key("GenerateManySpec_Other")
    end

    it "registers a class shared by several roots once" do
      parsed = JSON.parse(
        Lutaml::Model::Schema::JsonSchema.generate_many(
          [GenerateManySpec::Source, GenerateManySpec::Consumer],
        ),
      )

      expect(parsed["$defs"].keys.size).to eq(2)
      expect(parsed["$defs"]).to have_key("GenerateManySpec_Consumer")
    end

    it "formats YAML output" do
      yaml = Lutaml::Model::Schema::YamlSchema.generate_many(
        [GenerateManySpec::Source, GenerateManySpec::Other],
      )

      expect(yaml).to start_with("%YAML")
    end
  end

  describe "Generator::DefinitionsCollection.from_classes" do
    it "builds one collection covering all roots" do
      collection = Lutaml::Model::Schema::Generator::DefinitionsCollection
        .from_classes([GenerateManySpec::Source, GenerateManySpec::Consumer])

      expect(collection.to_schema.keys.size).to eq(2)
    end
  end
end
