# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema/definitions"
require "lutaml/model/schema/renderers/model"

RSpec.describe Lutaml::Model::Schema::Renderers::Model do
  let(:defs) { Lutaml::Model::Schema::Definitions }

  it "renders a rooted element with one element attribute" do
    spec = defs::Model.new(
      class_name: "Person",
      xml_root: defs::XmlRoot.new(kind: :element, name: "Person"),
      members: [
        defs::Attribute.new(
          name: "name",
          type: defs::TypeRef.new(kind: :symbol, value: "string"),
          xml_name: "name",
          kind: :element,
        ),
      ],
    )

    output = described_class.render(spec)

    expect(output).to include('class Person < Lutaml::Model::Serializable')
    expect(output).to include('attribute :name, :string')
    expect(output).to include('xml do')
    expect(output).to include('element "Person"')
    expect(output).to include('map_element "name", to: :name')
    expect(output).to include('def self.register')
    expect(output).to include('Person.register_class_with_id')
  end

  it "renders a fragment (no element / type_name directive)" do
    spec = defs::Model.new(
      class_name: "Inner",
      xml_root: defs::XmlRoot.new(kind: :fragment, name: nil),
    )

    output = described_class.render(spec)

    expect(output).not_to include("element ")
    expect(output).not_to include("type_name ")
  end

  it "renders an attribute mapping with map_attribute" do
    spec = defs::Model.new(
      class_name: "Item",
      xml_root: defs::XmlRoot.new(kind: :element, name: "Item"),
      members: [
        defs::Attribute.new(
          name: "id",
          type: defs::TypeRef.new(kind: :symbol, value: "string"),
          xml_name: "id",
          kind: :attribute,
        ),
      ],
    )

    output = described_class.render(spec)

    expect(output).to include('map_attribute "id", to: :id')
  end

  it "renders a class reference type with no leading colon" do
    spec = defs::Model.new(
      class_name: "Owner",
      xml_root: defs::XmlRoot.new(kind: :element, name: "Owner"),
      members: [
        defs::Attribute.new(
          name: "address",
          type: defs::TypeRef.new(kind: :class_ref, value: "Address"),
          xml_name: "address",
          kind: :element,
        ),
      ],
    )

    output = described_class.render(spec)

    expect(output).to include('attribute :address, Address')
  end

  it "renders a w3c type with the ::-prefixed reference" do
    spec = defs::Model.new(
      class_name: "Para",
      xml_root: defs::XmlRoot.new(kind: :element, name: "Para"),
      members: [
        defs::Attribute.new(
          name: "lang",
          type: defs::TypeRef.new(kind: :w3c, value: "Lutaml::Xml::W3c::Lang"),
          xml_name: "lang",
          kind: :attribute,
        ),
      ],
    )

    output = described_class.render(spec)

    expect(output).to include('attribute :lang, ::Lutaml::Xml::W3c::Lang')
  end

  it "skips register methods inside a module_namespace" do
    spec = defs::Model.new(
      class_name: "Inside",
      xml_root: defs::XmlRoot.new(kind: :element, name: "Inside"),
    )

    output = described_class.render(spec, module_namespace: "Mod::Sub")

    expect(output).to include("module Mod")
    expect(output).to include("module Sub")
    expect(output).not_to include("def self.register")
    expect(output).not_to include("register_class_with_id")
  end

  it "renders a choice block with attributes inside" do
    spec = defs::Model.new(
      class_name: "Either",
      xml_root: defs::XmlRoot.new(kind: :element, name: "Either"),
      members: [
        defs::Choice.new(
          header: "choice",
          alternatives: [
            defs::Attribute.new(
              name: "alpha",
              type: defs::TypeRef.new(kind: :symbol, value: "string"),
              xml_name: "alpha",
              kind: :element,
            ),
            defs::Attribute.new(
              name: "beta",
              type: defs::TypeRef.new(kind: :symbol, value: "string"),
              xml_name: "beta",
              kind: :element,
            ),
          ],
        ),
      ],
    )

    output = described_class.render(spec)

    expect(output).to include("choice do")
    expect(output).to include("attribute :alpha, :string")
    expect(output).to include("attribute :beta, :string")
  end
end
