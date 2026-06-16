# frozen_string_literal: true

require "spec_helper"

module UnionSpec
  class WithUnit < Lutaml::Model::Serializable
    attribute :number, :float
    attribute :unit, :string

    key_value do
      map "number", to: :number
      map "unit", to: :unit
    end
  end

  class Celsius < Lutaml::Model::Serializable
    attribute :celsius, :float

    key_value do
      map "celsius", to: :celsius
    end
  end
end

RSpec.describe Lutaml::Model::Type::Union do
  let(:int_str) do
    [Lutaml::Model::Type::Integer, Lutaml::Model::Type::String]
  end
  let(:int_float) do
    [Lutaml::Model::Type::Integer, Lutaml::Model::Type::Float]
  end

  def member_for(value, members, format: nil)
    result = described_class.conforming_member(value, members,
                                               format: format, register: nil)
    result&.first
  end

  describe ".conforming_member (scalars)" do
    it "matches Integer for an integer-lexical string" do
      expect(member_for("42", int_str)).to eq(Lutaml::Model::Type::Integer)
    end

    it "falls through to String when Integer rejects" do
      expect(member_for("hello", int_str)).to eq(Lutaml::Model::Type::String)
    end

    it "rejects a float-string for Integer (sound predicate, not Integer('3.7'))" do
      expect(member_for("3.7", int_float)).to eq(Lutaml::Model::Type::Float)
    end

    it "accepts a numeric integer string for the Integer member first" do
      expect(member_for("1300", int_float)).to eq(Lutaml::Model::Type::Integer)
    end

    it "matches a native Integer value" do
      expect(member_for(42, int_str)).to eq(Lutaml::Model::Type::Integer)
    end

    it "matches a native Float value to the Float member" do
      expect(member_for(3.7, int_float)).to eq(Lutaml::Model::Type::Float)
    end

    it "returns nil when no scalar member conforms" do
      expect(member_for("abc", int_float)).to be_nil
    end

    it "casts the value to the matched member" do
      member, casted = described_class.conforming_member(
        "42", int_str, format: nil, register: nil
      )
      expect([member, casted]).to eq([Lutaml::Model::Type::Integer, 42])
    end
  end

  describe ".conforming_member (boolean lexical space)" do
    let(:bool_str) do
      [Lutaml::Model::Type::Boolean, Lutaml::Model::Type::String]
    end

    it "matches a true/false word to Boolean" do
      expect(member_for("true", bool_str))
        .to eq(Lutaml::Model::Type::Boolean)
    end

    it "falls through to String for a non-boolean word" do
      expect(member_for("maybe", bool_str))
        .to eq(Lutaml::Model::Type::String)
    end
  end

  describe ".conforming_member (models by key-coverage)" do
    let(:members) { [UnionSpec::WithUnit, UnionSpec::Celsius] }

    it "selects the model whose fields cover the input keys" do
      member, = described_class.conforming_member(
        { "number" => 1300.0, "unit" => "C" }, members,
        format: :yaml, register: nil
      )
      expect(member).to eq(UnionSpec::WithUnit)
    end

    it "selects the disjoint-key model" do
      member, = described_class.conforming_member(
        { "celsius" => 1200.0 }, members, format: :yaml, register: nil
      )
      expect(member).to eq(UnionSpec::Celsius)
    end

    it "deserializes the selected model member" do
      _, value = described_class.conforming_member(
        { "celsius" => 1200.0 }, members, format: :yaml, register: nil
      )
      expect(value).to be_a(UnionSpec::Celsius)
      expect(value.celsius).to eq(1200.0)
    end

    it "returns nil when no model covers the keys" do
      result = described_class.conforming_member(
        { "unknown" => 1 }, members, format: :yaml, register: nil
      )
      expect(result).to be_nil
    end
  end

  describe "nil passthrough" do
    it "returns nil for nil input" do
      expect(member_for(nil, int_str)).to be_nil
    end
  end

  describe ".validate_members!" do
    it "raises on an empty member list" do
      expect { described_class.validate_members!([]) }
        .to raise_error(ArgumentError)
    end

    it "raises when a member is not a valid type" do
      expect { described_class.validate_members!([Object]) }
        .to raise_error(ArgumentError)
    end

    it "raises when a catch-all is not last" do
      expect do
        described_class.validate_members!(
          [Lutaml::Model::Type::String, Lutaml::Model::Type::Integer],
        )
      end.to raise_error(ArgumentError)
    end

    it "accepts a valid ordered member list" do
      expect do
        described_class.validate_members!(
          [Lutaml::Model::Type::Integer, Lutaml::Model::Type::String],
        )
      end.not_to raise_error
    end
  end

  describe ".validate_combo!" do
    it "raises when combined with polymorphic" do
      expect { described_class.validate_combo!(polymorphic: {}) }
        .to raise_error(ArgumentError)
    end

    it "raises when combined with raw" do
      expect { described_class.validate_combo!(raw: true) }
        .to raise_error(ArgumentError)
    end

    it "accepts a plain options hash" do
      expect { described_class.validate_combo!(collection: true) }
        .not_to raise_error
    end
  end

  describe "schema export" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :v,
                  [Lutaml::Model::Type::Integer, Lutaml::Model::Type::String]
        xml do
          root "union_schema_sample"
          map_element "v", to: :v
        end
        key_value { map "v", to: :v }

        def self.name
          "UnionSchemaSample"
        end
      end
    end

    it "emits anyOf for JSON Schema (valid if at least one member matches)" do
      schema = JSON.parse(Lutaml::Model::Schema::JsonSchema.generate(klass))
      defs = schema["$defs"] || schema["definitions"] || {}
      property = defs.dig("UnionSchemaSample", "properties", "v") ||
        schema.dig("properties", "v")

      expect(property).to eq(
        "anyOf" => [
          { "type" => "integer" },
          { "type" => "string" },
          { "type" => "null" },
        ],
      )
    end

    it "raises UnionSchemaUnsupportedError for XSD" do
      expect { Lutaml::Xml::Schema::XsdSchema.generate(klass) }
        .to raise_error(Lutaml::Model::UnionSchemaUnsupportedError)
    end

    it "raises UnionSchemaUnsupportedError for RelaxNG" do
      expect { Lutaml::Xml::Schema::RelaxngSchema.generate(klass) }
        .to raise_error(Lutaml::Model::UnionSchemaUnsupportedError)
    end
  end
end
