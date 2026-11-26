# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"
require "lutaml/lml/executor"
require "lutaml/lml/executor/csv_adapter"
require "tempfile"

RSpec.describe Lutaml::Lml::Executor::CsvAdapter do
  let(:component_klass) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :name, :string
      attribute :type, :string
      attribute :quantity, :string
    end
  end

  let(:compiled) { { "Component" => component_klass } }

  let(:csv_path) do
    File.expand_path("../../../fixtures/test_data/components.csv", __dir__)
  end

  let(:column_mapping_attributes) do
    [
      Lutaml::Lml::TopElementAttribute.new(name: "map_to", value: "Component"),
      Lutaml::Lml::TopElementAttribute.new(name: "id", value: "id"),
      Lutaml::Lml::TopElementAttribute.new(name: "name", value: "name"),
      Lutaml::Lml::TopElementAttribute.new(name: "type", value: "type"),
      Lutaml::Lml::TopElementAttribute.new(name: "quantity", value: "quantity")
    ]
  end

  describe ".import" do
    it "reads CSV and creates hydrated instances" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "csv",
        file: csv_path,
        attributes: column_mapping_attributes
      )

      result = described_class.import(imp, compiled: compiled)
      expect(result.length).to eq(3)
      expect(result[0].id).to eq("CPU001")
      expect(result[0].name).to eq("CPU")
      expect(result[1].name).to eq("GPU")
      expect(result[2].quantity).to eq("4")
    end

    it "returns empty array for missing file" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "csv",
        file: "/nonexistent/path.csv"
      )
      result = described_class.import(imp, compiled: compiled)
      expect(result).to eq([])
    end

    it "returns empty array when no map_to attribute" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "csv",
        file: csv_path
      )
      result = described_class.import(imp, compiled: compiled)
      expect(result).to eq([])
    end

    it "returns empty array when no attributes" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "csv",
        file: csv_path,
        attributes: []
      )
      result = described_class.import(imp, compiled: compiled)
      expect(result).to eq([])
    end

    it "maps columns with different attribute names" do
      attrs = [
        Lutaml::Lml::TopElementAttribute.new(name: "map_to", value: "Component"),
        Lutaml::Lml::TopElementAttribute.new(name: "id", value: "id"),
        Lutaml::Lml::TopElementAttribute.new(name: "name", value: "name")
      ]
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "csv",
        file: csv_path,
        attributes: attrs
      )

      result = described_class.import(imp, compiled: compiled)
      expect(result.length).to eq(3)
      expect(result[0].id).to eq("CPU001")
      expect(result[0].name).to eq("CPU")
      expect(result[0].type).to be_nil
    end
  end

  describe ".export" do
    it "writes instances to CSV file" do
      instances = [
        component_klass.new(id: "A1", name: "Alpha", type: "test", quantity: "1"),
        component_klass.new(id: "B2", name: "Beta", type: "test", quantity: "2")
      ]

      file = Tempfile.new(%w[export .csv])
      file.close
      export_attrs = [
        Lutaml::Lml::TopElementAttribute.new(name: "file", value: file.path)
      ]
      exp = Lutaml::Lml::InstancesExport.new(
        format_type: "csv",
        attributes: export_attrs
      )

      described_class.export(exp, instances, compiled: compiled)

      content = File.read(file.path)
      expect(content).to include("id,name,type,quantity")
      expect(content).to include("A1,Alpha,test,1")
      expect(content).to include("B2,Beta,test,2")
      file.unlink
    end

    it "does nothing when instances array is empty" do
      file = Tempfile.new(%w[export .csv])
      file.close
      export_attrs = [
        Lutaml::Lml::TopElementAttribute.new(name: "file", value: file.path)
      ]
      exp = Lutaml::Lml::InstancesExport.new(
        format_type: "csv",
        attributes: export_attrs
      )

      described_class.export(exp, [], compiled: compiled)
      expect(File.size(file.path)).to eq(0)
      file.unlink
    end

    it "does nothing when no file attribute" do
      instances = [component_klass.new(id: "A1", name: "Alpha")]
      exp = Lutaml::Lml::InstancesExport.new(
        format_type: "csv",
        attributes: []
      )

      expect { described_class.export(exp, instances, compiled: compiled) }.not_to raise_error
    end
  end
end
