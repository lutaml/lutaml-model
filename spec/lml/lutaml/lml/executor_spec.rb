# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "lutaml/lml/executor"

RSpec.describe Lutaml::Lml::Executor do
  describe ".run" do
    it "returns Result with empty instances when no imports" do
      doc = Lutaml::Lml::Document.new
      result = described_class.run(doc, compiled: {})
      expect(result.instances).to eq([])
      expect(result.errors).to eq([])
    end

    it "returns Result with empty instances when no instances block" do
      doc = Lutaml::Lml::Document.new
      result = described_class.run(doc, compiled: {})
      expect(result.instances).to eq([])
      expect(result.errors).to eq([])
    end

    it "runs imports via registered adapter" do
      test_adapter = Class.new do
        def self.import(_imp, compiled:)
          [Struct.new(:name).new("test_item")]
        end

        def self.export(_exp, _instances, compiled:)
          nil
        end
      end
      Lutaml::Lml::Executor::FormatAdapter.register("test", test_adapter)

      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "test",
        file: "test.dat"
      )
      instances = Lutaml::Lml::InstanceCollection.new(imports: [imp])
      doc = Lutaml::Lml::Document.new(instances: instances)

      result = described_class.run(doc, compiled: {})
      expect(result.length).to eq(1)
      expect(result[0].name).to eq("test_item")
    end

    it "raises AdapterNotFoundError for unknown import format" do
      imp = Lutaml::Lml::InstancesImport.new(
        format_type: "unknown_format",
        file: "test.dat"
      )
      instances = Lutaml::Lml::InstanceCollection.new(imports: [imp])
      doc = Lutaml::Lml::Document.new(instances: instances)

      expect { described_class.run(doc, compiled: {}) }
        .to raise_error(Lutaml::Lml::Executor::FormatAdapter::AdapterNotFoundError)
    end

    it "collects validation errors from every collection block" do
      instances = Lutaml::Lml::InstanceCollection.new(
        collections: [
          Lutaml::Lml::Collection.new(name: "a", validations: ["count >= 1"]),
          Lutaml::Lml::Collection.new(name: "b", validations: ["count >= 2"])
        ]
      )
      doc = Lutaml::Lml::Document.new(instances: instances)

      result = described_class.run(doc, compiled: {})
      expect(result.instances).to eq([])
      expect(result.errors).to include(
        a_string_matching(/count >= 1/),
        a_string_matching(/count >= 2/)
      )
    end
  end
end
