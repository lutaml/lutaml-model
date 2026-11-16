# frozen_string_literal: true

# lutaml-model#1130: a VALUED :child_deferred row (the cycle-point
# spelling — the OOXML bibliography's Author → author same-class
# recursion) must keep the DOM lane. The native ordered replay has no
# ops spelling for the island: its nested rows render as scalar
# placeholders and the data drops (<b:Author/>). The gate previously
# skipped child_deferred rows outright, admitting the native lane for
# exactly the shape it cannot address.

require "lutaml/model"
require "lutaml/xml/leptris"

module Bib1130
  class BNamespace < Lutaml::Xml::Namespace
    uri "http://schemas.openxmlformats.org/officeDocument/2006/bibliography"
    prefix_default "b"
  end

  class Person < Lutaml::Model::Serializable
    attribute :last, :string
    attribute :first, :string
    attribute :middle, :string

    xml do
      element "Person"
      namespace BNamespace
      mixed_content
      map_element "Last", to: :last
      map_element "First", to: :first, render_nil: false
      map_element "Middle", to: :middle, render_nil: false
    end
  end

  class NameList < Lutaml::Model::Serializable
    attribute :person, Person, collection: true, initialize_empty: true

    xml do
      element "NameList"
      namespace BNamespace
      mixed_content
      map_element "Person", to: :person, render_nil: false
    end
  end

  class Author < Lutaml::Model::Serializable
    attribute :name_list, NameList
    attribute :author, Author

    xml do
      element "Author"
      namespace BNamespace
      mixed_content
      map_element "NameList", to: :name_list, render_nil: false
      map_element "Author", to: :author, render_nil: false
    end
  end

  class Source < Lutaml::Model::Serializable
    attribute :source_type, :string
    attribute :author, Author
    attribute :title, :string

    xml do
      element "Source"
      namespace BNamespace
      mixed_content
      map_element "SourceType", to: :source_type, render_nil: false
      map_element "Author", to: :author, render_nil: false
      map_element "Title", to: :title, render_nil: false
    end
  end

  class Sources < Lutaml::Model::Serializable
    attribute :source, Source, collection: true

    xml do
      element "Sources"
      namespace BNamespace
      mixed_content
      map_element "Source", to: :source, render_nil: false
    end
  end
end

RSpec.describe "valued child_deferred rows keep the DOM lane (#1130)" do
  let(:xml) do
    <<~XML
      <b:Sources xmlns:b="http://schemas.openxmlformats.org/officeDocument/2006/bibliography">
        <b:Source><b:SourceType>Book</b:SourceType>
          <b:Author><b:Author><b:NameList><b:Person><b:Last>Last Name</b:Last><b:First>First,</b:First><b:Middle>Middle</b:Middle></b:Person></b:NameList></b:Author></b:Author>
          <b:Title>Book Title</b:Title>
        </b:Source>
      </b:Sources>
    XML
  end

  it "round-trips the nested same-element chain with both fast-path states" do
    [true, false].each do |fast|
      Lutaml::Model::Config.instance.xml_plan_fast_path = fast
      parsed = Bib1130::Sources.from_xml(xml)
      inner = parsed.source.first.author.author

      expect(inner.name_list.person.first.last).to eq("Last Name")

      out = parsed.to_xml
      expect(out).not_to include("<b:Author/>")
      expect(out).to include("Last Name")
    end
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
  end

  it "refuses the native lane for the valued deferred plan" do
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
    parsed = Bib1130::Sources.from_xml(xml)
    src = parsed.source.first
    plan = Lutaml::Xml::Leptris::PlanCompiler.compile(
      src.class, Lutaml::Model::Config.default_register
    )
    expect(
      Lutaml::Xml::Leptris::NativeEmission.compatible?(
        plan, src, Lutaml::Model::Config.default_register
      ),
    ).to be(false)
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
  end
end
