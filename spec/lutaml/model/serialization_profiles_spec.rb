# frozen_string_literal: true

require "spec_helper"

# Serialization mapping profiles (#176): multiple serialization models of
# the same format over one data model. A named mapping is a complete
# projection; selection is per call via `mapping:`; the base mapping
# stays the default. Runtime-constructed mapping objects wire with
# `mapping :name, mapping`.
module SerializationProfilesSpec
  class Person < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :email, :string
    attribute :internal_id, :string

    json do
      map "name", to: :name
      map "email", to: :email
      map "internal_id", to: :internal_id
    end

    json :compact do
      map "name", to: :name
    end

    yaml do
      map "name", to: :name
      map "email", to: :email
    end

    yaml :public do
      map "full_name", to: :name
    end
  end

  class Badge < Lutaml::Model::Serializable
    attribute :code, :string

    json do
      map "code", to: :code
    end
  end

  class Employee < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :badge, Badge

    json do
      map "name", to: :name
      map "badge", to: :badge
    end

    json :slim do
      map "name", to: :name
    end
  end

  class Collecting < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :extras, :hash

    json do
      map "name", to: :name
      map_unmapped to: :extras
    end

    json :only_name do
      map "name", to: :name
      map_unmapped to: :extras
    end

    hsh :only_name do
      map "name", to: :name
    end
  end

  class Record < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :email, :string

    xml do
      root "record"
      map_element "name", to: :name
      map_element "email", to: :email
    end

    xml :registry do
      root "registry-entry"
      map_attribute "name", to: :name
    end
  end

  RSpec.describe "Serialization mapping profiles" do
    let(:person) do
      Person.new(name: "Ed", email: "ed@example.com", internal_id: "42")
    end

    it "serializes with the base mapping when no profile is selected" do
      expect(person.to_json).to eq(
        '{"name":"Ed","email":"ed@example.com","internal_id":"42"}',
      )
    end

    it "serializes through a declared named mapping" do
      expect(person.to_json(mapping: :compact)).to eq('{"name":"Ed"}')
    end

    it "parses through the same named mapping symmetrically" do
      model = Person.from_json('{"name":"Ed"}', mapping: :compact)

      expect(model.name).to eq("Ed")
      expect(model.email).to be_nil
      expect(model.internal_id).to be_nil
    end

    it "keeps the base mapping isolated from profile calls" do
      3.times do
        person.to_json(mapping: :compact)
        expect(person.to_json).to include("internal_id")
      end
    end

    it "supports named mappings on other formats independently" do
      expect(person.to_yaml(mapping: :public)).to eq("---\nfull_name: Ed\n")
      expect(person.to_yaml).to eq("---\nname: Ed\nemail: ed@example.com\n")
    end

    it "raises UnknownMappingError for an undeclared profile name" do
      expect { person.to_json(mapping: :nope) }
        .to raise_error(Lutaml::Model::UnknownMappingError, /:nope/)
      expect { Person.from_json("{}", mapping: :nope) }
        .to raise_error(Lutaml::Model::UnknownMappingError)
    end

    it "selects through a mapping instance directly" do
      mapping = Lutaml::Model::Config.mappings_class_for(:json).new
      mapping.map "the_name", to: :name

      expect(person.to_json(mapping: mapping)).to eq('{"the_name":"Ed"}')
    end

    it "rejects a mapping instance of another format" do
      yaml_mapping = Lutaml::Model::Config.mappings_class_for(:yaml).new

      expect { person.to_json(mapping: yaml_mapping) }
        .to raise_error(ArgumentError, /must be a Lutaml::Json::Adapter::Mapping/)
    end

    it "wires a runtime-constructed mapping under a name" do
      mapping = Lutaml::Model::Config.mappings_class_for(:yaml).new
      mapping.map "contact", to: :email
      Person.mapping :contact, mapping

      expect(person.to_yaml(mapping: :contact)).to eq("---\ncontact: ed@example.com\n")
    end

    it "infers the format of a wired mapping and validates its class" do
      json_mapping = Lutaml::Model::Config.mappings_class_for(:json).new
      json_mapping.map "n", to: :name
      Person.mapping :short, json_mapping

      expect(person.to_json(mapping: :short)).to eq('{"n":"Ed"}')
      expect { Person.mapping :bad, json_mapping, format: :yaml }
        .to raise_error(ArgumentError, /mapping class/)
    end

    it "removes a wired mapping with a nil mapping object" do
      mapping = Lutaml::Model::Config.mappings_class_for(:json).new
      mapping.map "n", to: :name
      Person.mapping :temp, mapping
      expect(person.to_json(mapping: :temp)).to eq('{"n":"Ed"}')

      Person.mapping :temp, nil, format: :json
      expect(Person.serialization_mappings(:json)).not_to have_key(:temp)
      expect { person.to_json(mapping: :temp) }
        .to raise_error(Lutaml::Model::UnknownMappingError)
    end

    it "lists declared profiles through serialization_mappings" do
      stub_const("IsoOnly", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        json do
          map "name", to: :name
        end

        json :iso do
          map "iso_name", to: :name
        end
      end)

      expect(IsoOnly.serialization_mappings(:json).keys)
        .to contain_exactly(:iso)
      expect(IsoOnly.serialization_mappings(:toml)).to eq({})
    end

    it "replaces a profile on re-declaration" do
      Person.json :compact do
        map "codename", to: :name
      end

      expect(person.to_json(mapping: :compact)).to eq('{"codename":"Ed"}')
    end

    it "composes only: with a selected profile" do
      expect(person.to_json(mapping: :compact, except: [:name])).to eq("{}")
    end

    it "keeps child models on their own base mapping" do
      employee = Employee.new(name: "Ed", badge: Badge.new(code: "B1"))

      expect(employee.to_json(mapping: :slim)).to eq('{"name":"Ed"}')
      expect(employee.to_json).to eq(
        '{"name":"Ed","badge":{"code":"B1"}}',
      )
    end

    it "collects map_unmapped keys per profile" do
      model = Collecting.from_json(
        '{"name":"Ed","surprise":1}', mapping: :only_name
      )

      expect(model.extras).to eq("surprise" => 1)

      collected = Collecting.from_json('{"name":"Ed","surprise":1}')

      expect(collected.extras).to eq("surprise" => 1)
    end

    it "serializes a named XML profile with its own root and mappings" do
      record = Record.new(name: "Ed", email: "ed@example.com")

      expect(record.to_xml(mapping: :registry).strip)
        .to eq("<registry-entry name=\"Ed\"/>")
    end

    it "parses a named XML profile symmetrically" do
      model = Record.from_xml("<registry-entry name=\"Ed\"/>",
                              mapping: :registry)

      expect(model.name).to eq("Ed")
      expect(model.email).to be_uninitialized
    end

    it "keeps the base XML mapping isolated from profile calls" do
      record = Record.new(name: "Ed", email: "ed@example.com")
      base = record.to_xml

      record.to_xml(mapping: :registry)
      expect(record.to_xml).to eq(base)
      expect(base).to include("<name>Ed</name>")
    end

    it "round-trips a profile over the hash format" do
      model = Collecting.new(name: "Ed")

      expect(model.to_hash(mapping: :only_name)).to eq("name" => "Ed")
    end
  end
end
