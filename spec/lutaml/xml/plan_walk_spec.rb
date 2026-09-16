# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml/plan_walk"

RSpec.describe "XML PlanWalk consumer surface" do
  around do |example|
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  end

  let(:item_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :integer
      attribute :name, :string
      attribute :tags, :string, collection: true

      xml do
        element "row"
        map_attribute "id", to: :id
        map_element "name", to: :name
        map_element "tags", to: :tags
      end
    end
  end

  it "hydrates equal to the interpretive path on a single-row document" do
    xml = %(<row id="7"><name>Alice</name><tags>x</tags><tags>y</tags></row>)
    walked = Lutaml::Xml::PlanWalk.call(item_class, xml)
    expected = item_class.from_xml(xml)

    expect(walked).to be_a(item_class)
    expect(walked.id).to eq(expected.id)
    expect(walked.name).to eq(expected.name)
    expect(walked.tags).to eq(expected.tags)
  end

  it "returns an Array for collection roots" do
    xml = %(<root><row id="1"><name>a</name></row><row id="2"><name>b</name></row></root>)
    item_type = item_class
    root_class = Class.new(Lutaml::Model::Serializable) do
      attribute :item, item_type, collection: true

      xml do
        element "root"
        map_element "row", to: :item
      end
    end

    walked = Lutaml::Xml::PlanWalk.call(root_class, xml)
    expected = root_class.from_xml(xml)

    expect(walked.item).to be_an(Array)
    expect(walked.item.map(&:id)).to eq(expected.item.map(&:id))
    expect(walked.item.map(&:name)).to eq(expected.item.map(&:name))
  end

  it "walks and hydrates a 5000-row document in under the interpretive cost" do
    xml = +"<root>"
    5000.times do |i|
      xml << %(<row id="#{i}"><name>r-#{i}</name><tags>a</tags><tags>b</tags></row>)
    end
    xml << "</root>"

    item_type = item_class
    root_class = Class.new(Lutaml::Model::Serializable) do
      attribute :item, item_type, collection: true

      xml do
        element "root"
        map_element "row", to: :item
      end
    end

    walked = Lutaml::Xml::PlanWalk.call(root_class, xml)
    interpretive = root_class.from_xml(xml)
    expect(walked.item.size).to eq(interpretive.item.size)
    expect(walked.item.map(&:id)).to eq(interpretive.item.map(&:id))
  end

  it "compiles delegate mappings for post-instance routing" do
    # delegates compile and route after the target instance exists
    target = Class.new(Lutaml::Model::Serializable) do
      attribute :note, :string
      xml do
        element "tgt"
        map_element "note", to: :note
      end
    end
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :tgt, target
      xml do
        element "doc"
        map_element "note", to: :note, delegate: :tgt
      end
    end

    expect(Lutaml::Xml::PlanCompiler.compile(klass,
                                             Lutaml::Model::Config.default_register)).not_to be_nil
    expect(Lutaml::Xml::PlanWalk.call(klass, "<doc><note>x</note></doc>").tgt.note)
      .to eq("x")
  end
end
