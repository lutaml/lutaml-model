# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML with REXML under Opal", if: RUBY_ENGINE == "opal" do
  before do
    Lutaml::Model::Config.xml_adapter_type = :rexml
  end

  it "round-trips XML through parse and serialize" do
    klass = Class.new do
      include Lutaml::Model::Serialize

      attribute :name, :string
      xml do
        root "person"
        map_element "name", to: :name
      end
    end

    instance = klass.from_xml("<person><name>Alice</name></person>")
    expect(instance.name).to eq("Alice")
    expect(instance.to_xml).to include("<name>Alice</name>")
  end

  it "handles XML attributes" do
    klass = Class.new do
      include Lutaml::Model::Serialize

      attribute :id, :string
      attribute :value, :string
      xml do
        root "item"
        map_attribute "id", to: :id
        map_element "value", to: :value
      end
    end

    instance = klass.from_xml('<item id="42"><value>test</value></item>')
    expect(instance.id).to eq("42")
    expect(instance.value).to eq("test")
  end

  it "handles nested elements" do
    address = Class.new do
      include Lutaml::Model::Serialize

      attribute :city, :string
      xml do
        root "address"
        map_element "city", to: :city
      end
    end

    person = Class.new do
      include Lutaml::Model::Serialize

      attribute :name, :string
      attribute :address, address
      xml do
        root "person"
        map_element "name", to: :name
        map_element "address", to: :address
      end
    end

    instance = person.from_xml("<person><name>Alice</name><address><city>NYC</city></address></person>")
    expect(instance.name).to eq("Alice")
    expect(instance.address.city).to eq("NYC")
  end

  it "handles element collections" do
    list = Class.new do
      include Lutaml::Model::Serialize

      attribute :items, :string, collection: true
      xml do
        root "list"
        map_element "item", to: :items
      end
    end

    instance = list.from_xml("<list><item>a</item><item>b</item><item>c</item></list>")
    expect(instance.items).to eq(%w[a b c])
  end

  it "handles mixed content" do
    paragraph = Class.new do
      include Lutaml::Model::Serialize

      attribute :content, :string, collection: true
      xml do
        root "p"
        mixed_content
        map_content to: :content
      end
    end

    instance = paragraph.from_xml("<p>Hello <b>world</b> end</p>")
    expect(instance.content.join).to include("Hello")
  end

  it "serializes to XML with correct structure" do
    item = Class.new do
      include Lutaml::Model::Serialize

      attribute :title, :string
      attribute :count, :integer
      xml do
        root "item"
        map_element "title", to: :title
        map_element "count", to: :count
      end
    end

    instance = item.new(title: "Widget", count: 5)
    xml = instance.to_xml
    expect(xml).to include("<title>Widget</title>")
    expect(xml).to include("<count>5</count>")
  end

  it "handles XmlOrderable on plain model classes" do
    plain_model = Class.new do
      attr_accessor :data
    end

    Class.new do
      include Lutaml::Model::Serialize

      const_set(:MODEL_CLASS, plain_model)
      model plain_model
      attribute :data, :string
      xml do
        root "data"
        map_element "data", to: :data
      end
    end

    expect(plain_model.ancestors).to include(Lutaml::Xml::XmlOrderable)
  end

  it "uses REXML adapter by default under Opal" do
    expect(Lutaml::Model::Config.xml_adapter_type).to eq(:rexml)
  end
end
