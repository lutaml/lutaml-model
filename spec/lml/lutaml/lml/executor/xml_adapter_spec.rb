# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"
require "lutaml/lml/executor"
require "lutaml/lml/executor/xml_adapter"
require "tempfile"

RSpec.describe Lutaml::Lml::Executor::XmlAdapter do
  # Mirrors what ModelCompiler produces: a Serializable subclass with
  # lutaml-model XML mapping applied for from_xml/to_xml support.
  def self.make_product_class(attr_specs)
    Class.new(Lutaml::Model::Serializable) do
      attr_specs.each do |name, type|
        attribute name, type
      end

      xml do |mapping|
        mapping.root("Product")
        attr_specs.each do |name, _type|
          mapping.map_element(name.to_s, to: name)
        end
      end
    end
  end

  let(:product_klass) do
    self.class.make_product_class(id: :string, name: :string, price: :string)
  end

  let(:compiled) { { "Product" => product_klass } }

  let(:xml_path) do
    File.expand_path("../../../fixtures/test_data/products.xml", __dir__)
  end

  describe ".import" do
    it "reads XML and creates hydrated instances" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "xml",
        file: xml_path,
        attributes: [
          Lutaml::Lml::TopElementAttribute.new(name: "map_to", value: "Product"),
          Lutaml::Lml::TopElementAttribute.new(name: "where", value: "/Products/Product")
        ]
      )

      result = described_class.import(imp, compiled: compiled)
      expect(result.length).to eq(3)
      expect(result[0].id).to eq("P001")
      expect(result[0].name).to eq("Widget")
      expect(result[2].name).to eq("Gizmo")
    end

    it "returns empty array for missing file" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "xml",
        file: "/nonexistent/path.xml",
        attributes: [
          Lutaml::Lml::TopElementAttribute.new(name: "map_to", value: "Product"),
          Lutaml::Lml::TopElementAttribute.new(name: "where", value: "/Products/Product")
        ]
      )
      expect(described_class.import(imp, compiled: compiled)).to eq([])
    end

    it "returns empty array when no map_to attribute" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "xml",
        file: xml_path,
        attributes: []
      )
      expect(described_class.import(imp, compiled: compiled)).to eq([])
    end

    it "returns empty array when no attributes" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "xml",
        file: xml_path
      )
      expect(described_class.import(imp, compiled: compiled)).to eq([])
    end

    it "uses default selector when where is missing" do
      xml = Tempfile.new(%w[products .xml])
      xml.write(<<~XML)
        <Root><Product><id>X</id><name>Default</name></Product></Root>
      XML
      xml.close

      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "xml",
        file: xml.path,
        attributes: [
          Lutaml::Lml::TopElementAttribute.new(name: "map_to", value: "Product")
        ]
      )

      result = described_class.import(imp, compiled: compiled)
      expect(result.length).to eq(1)
      expect(result[0].id).to eq("X")
      xml.unlink
    end
  end

  describe ".export" do
    it "writes instances to XML file" do
      instances = [
        product_klass.new(id: "P1", name: "Alpha", price: "1.00"),
        product_klass.new(id: "P2", name: "Beta", price: "2.00")
      ]

      file = Tempfile.new(%w[export .xml])
      file.close
      exp = Lutaml::Lml::InstancesExport.new(
        format_type: "xml",
        attributes: [
          Lutaml::Lml::TopElementAttribute.new(name: "file", value: file.path),
          Lutaml::Lml::TopElementAttribute.new(name: "root", value: "Products")
        ]
      )

      described_class.export(exp, instances, compiled: compiled)

      content = File.read(file.path)
      expect(content).to include("<Products>")
      expect(content).to include("<id>P1</id>")
      expect(content).to include("<name>Alpha</name>")
      expect(content).to include("<id>P2</id>")
      expect(content).to include("</Products>")
      file.unlink
    end

    it "does nothing when instances array is empty" do
      file = Tempfile.new(%w[export .xml])
      file.close
      exp = Lutaml::Lml::InstancesExport.new(
        format_type: "xml",
        attributes: [
          Lutaml::Lml::TopElementAttribute.new(name: "file", value: file.path)
        ]
      )

      described_class.export(exp, [], compiled: compiled)
      expect(File.size(file.path)).to eq(0)
      file.unlink
    end

    it "does nothing when no file attribute" do
      instances = [product_klass.new(id: "P1", name: "Alpha")]
      exp = Lutaml::Lml::InstancesExport.new(format_type: "xml", attributes: [])

      expect { described_class.export(exp, instances, compiled: compiled) }.not_to raise_error
    end

    it "uses compiled class name as default root" do
      instances = [product_klass.new(id: "P1", name: "Alpha", price: "5")]

      file = Tempfile.new(%w[export .xml])
      file.close
      exp = Lutaml::Lml::InstancesExport.new(
        format_type: "xml",
        attributes: [
          Lutaml::Lml::TopElementAttribute.new(name: "file", value: file.path)
        ]
      )

      described_class.export(exp, instances, compiled: compiled)
      content = File.read(file.path)
      expect(content).to include("<Products>")
      expect(content).to include("<Product>")
      file.unlink
    end

    it "writes wrapper-level unindented XML when indent is false" do
      instances = [product_klass.new(id: "P1", name: "Alpha")]

      file = Tempfile.new(%w[export .xml])
      file.close
      exp = Lutaml::Lml::InstancesExport.new(
        format_type: "xml",
        attributes: [
          Lutaml::Lml::TopElementAttribute.new(name: "file", value: file.path),
          Lutaml::Lml::TopElementAttribute.new(name: "indent", value: "false")
        ]
      )

      described_class.export(exp, instances, compiled: compiled)
      content = File.read(file.path)
      # With indent: false, the wrapper places records on the same line.
      expect(content).to include("<Products><Product>")
      file.unlink
    end
  end

  describe "FormatAdapter registry" do
    it "is registered for the xml format" do
      expect(Lutaml::Lml::Executor::FormatAdapter.resolve("xml")).to eq(described_class)
    end
  end
end