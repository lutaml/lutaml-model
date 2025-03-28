require "benchmark"
require "benchmark/ips"
require "lutaml/model"
require "lutaml/model/xml/oga_adapter"

RSpec.describe "LutaML Model Performance" do
  after do
    Lutaml::Model::Config.xml_adapter = Lutaml::Model::Xml::NokogiriAdapter
  end

  let(:large_xml) do
    xml = "<root>\n"
    1000.times do |i|
      xml += "<item id='#{i}'><name>Test #{i}</name><value>#{i}</value></item>\n"
    end
    xml += "</root>"
    xml
  end

  class DeserializerItem < Lutaml::Model::Serializable
    attribute :id, :integer
    attribute :name, :string
    attribute :value, :integer

    xml do
      map_attribute "id", to: :id
      map_element "value", to: :value
      map_element "name", to: :name
      map_element "value", to: :value
    end
  end

  class Deserializer < Lutaml::Model::Serializable
    attribute :item, DeserializerItem, collection: true

    xml do
      root "root"
      map_element "item", to: :item
    end
  end

  it "measures parsing performance across adapters" do
    report = Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)

      x.report("Nokogiri Adapter") do
        Deserializer.from_xml(large_xml)
      end

      x.report("Ox Adapter") do
        Lutaml::Model::Config.xml_adapter = Lutaml::Model::Xml::OxAdapter
        Deserializer.from_xml(large_xml)
      end

      x.report("Oga Adapter") do
        Lutaml::Model::Config.xml_adapter = Lutaml::Model::Xml::OgaAdapter
        Deserializer.from_xml(large_xml)
      end

      x.compare!
    end

    thresholds = {
      "Nokogiri Adapter" => 3,
      "Ox Adapter" => 7,
      "Oga Adapter" => 3,
    }

    report.entries.each do |entry|
      puts "#{entry.label} performance: #{entry.ips.round(2)} ips"
      expect(entry.ips).to be >= thresholds[entry.label],
                           "#{entry.label} performance below threshold: got #{entry.ips.round(2)} ips, expected >= #{thresholds[entry.label]} ips"
    end
  end
end
