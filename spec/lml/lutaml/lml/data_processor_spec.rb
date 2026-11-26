# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe Lutaml::Lml::DataProcessor do
  let(:processor) { described_class.new }

  describe ".process" do
    it "processes data without requiring a mixin" do
      input = { name: "test" }
      result = described_class.process(input)
      expect(result).to eq({ name: "test" })
    end

    it "processes key handlers via class method" do
      input = { attributes: [{ key: "name", value: { string: "test" } }] }
      result = described_class.process(input)
      expect(result[:attributes].first[:name]).to eq("name")
    end
  end

  describe "#process_data" do
    it "passes through non-hash/array values" do
      expect(processor.process_data("hello")).to eq("hello")
      expect(processor.process_data(42)).to eq(42)
    end

    it "recursively processes arrays" do
      input = [{ name: "test" }, { key: "value" }]
      result = processor.process_data(input)
      expect(result).to be_an(Array)
    end

    it "recursively processes hashes" do
      input = { name: "test", nested: { key: "val" } }
      result = processor.process_data(input)
      expect(result).to be_a(Hash)
    end

    it "does not mutate the input hash" do
      original = { requires: [{ require: { string: "file.lml" } }], name: "test" }
      original_frozen = original.dup
      processor.process_data(original)
      expect(original).to eq(original_frozen)
    end
  end

  describe "#process_value" do
    it "returns empty array for nil" do
      expect(processor.process_value(nil)).to eq([])
    end

    it "processes string hash" do
      result = processor.process_value({ string: "hello" })
      expect(result).to eq(["String", "hello"])
    end

    it "processes boolean hash with true" do
      result = processor.process_value({ boolean: "true" })
      expect(result).to eq(["Boolean", true])
    end

    it "processes boolean hash with false" do
      result = processor.process_value({ boolean: "false" })
      expect(result).to eq(["Boolean", false])
    end

    it "processes number hash" do
      result = processor.process_value({ number: "42" })
      expect(result).to eq(["Number", 42])
    end

    it "processes list hash" do
      result = processor.process_value({ list: [{ string: "a" }, { string: "b" }] })
      expect(result[0]).to eq("String[]")
      expect(result[1]).to eq(%w[a b])
    end

    it "processes key_value_map" do
      input = {
        key_value_map: [
          { key: "name", value: { string: "test" } },
          { key: "count", value: { number: "5" } }
        ]
      }
      result = processor.process_value(input)
      expect(result[0]).to eq("Hash")
      expect(result[1][:name]).to eq("test")
      expect(result[1][:count]).to eq(5)
    end

    it "processes instance values" do
      result = processor.process_value({ instance: { instance_type: "MyClass" } })
      expect(result[0]).to eq("Instance")
      expect(result[1]).to be_a(Hash)
    end

    it "processes condition values by unwrapping" do
      result = processor.process_value({ condition: { string: "x > 0" } })
      expect(result).to eq(["String", "x > 0"])
    end

    it "processes require values by unwrapping" do
      result = processor.process_value({ require: { string: "file.lml" } })
      expect(result).to eq(["String", "file.lml"])
    end

    it "processes plain arrays" do
      result = processor.process_value([{ string: "a" }, { string: "b" }])
      expect(result[0]).to eq("String[]")
      expect(result[1]).to eq(%w[a b])
    end

    it "falls back to class name for unknown types" do
      result = processor.process_value(3.14)
      expect(result).to eq(["Float", 3.14])
    end
  end

  describe "#process_instance" do
    it "converts instance_type to type" do
      result = processor.process_instance({ instance_type: "MyClass" })
      expect(result[:type]).to eq("MyClass")
    end

    it "preserves nested instance" do
      input = {
        instance_type: "Parent",
        instance: { instance_type: "Child" }
      }
      result = processor.process_instance(input)
      expect(result[:type]).to eq("Parent")
      expect(result[:instance][:type]).to eq("Child")
    end

    it "processes attributes" do
      input = {
        instance_type: "MyClass",
        attributes: [
          { key: "name", value: { string: "test" } }
        ]
      }
      result = processor.process_instance(input)
      expect(result[:type]).to eq("MyClass")
      expect(result[:attributes]).to be_an(Array)
      expect(result[:attributes].first[:name]).to eq("name")
    end

    it "processes template" do
      input = {
        instance_type: "MyClass",
        template: {
          attributes: [{ key: "component", value: { string: "cpu" } }]
        }
      }
      result = processor.process_instance(input)
      expect(result[:template]).to be_an(Array)
      expect(result[:template].first[:name]).to eq("component")
    end
  end

  describe "#process_attributes" do
    it "converts key to name in hash form" do
      result = processor.process_attributes_hash({ key: "foo", value: { string: "bar" } })
      expect(result[:name]).to eq("foo")
      expect(result[:value]).to eq("bar")
    end

    it "converts comments to Comment name/value" do
      result = processor.process_attributes_hash({ comments: { string: "note" } })
      expect(result[:name]).to eq("Comment")
      expect(result[:value]).to eq("note")
    end

    it "sets extended flag from add key" do
      result = processor.process_attributes_hash({ key: "prop", value: { string: "x" }, add: "true" })
      expect(result[:extended]).to eq(true)
    end

    it "converts Instance type values to instances" do
      result = processor.process_attributes_hash({
        key: "items",
        value: { instance: { instance_type: "Item" } }
      })
      expect(result).to have_key(:instances)
      expect(result[:instances].length).to eq(1)
    end

    it "returns an empty array for an empty attributes body" do
      expect(processor.process_attributes_array([])).to eq([])
    end
  end

  describe "#process_requires" do
    it "extracts string values from require entries" do
      result = processor.process_requires([{ require: { string: "file1.lml" } }])
      expect(result).to eq(["file1.lml"])
    end
  end

  describe "#process_collections" do
    it "processes collection values" do
      input = { name: { string: "suite1" }, "includes": [{ string: "a" }, { string: "b" }] }
      result = processor.process_collections(input)
      expect(result[:name]).to eq("suite1")
    end
  end

  describe "#process_imports" do
    it "processes import entries with attributes" do
      input = [{
        format_type: "xml",
        file: "data.xml",
        attributes: [{ key: "map_to", value: { string: "Product" } }]
      }]
      result = processor.process_imports(input)
      expect(result.length).to eq(1)
      expect(result[0][:format_type]).to eq("xml")
      expect(result[0][:file]).to eq("data.xml")
    end
  end

  describe "#process_exports" do
    it "processes export entries" do
      input = [{
        format_type: "json",
        attributes: [{ key: "indent", value: { boolean: "true" } }]
      }]
      result = processor.process_exports(input)
      expect(result[0][:format_type]).to eq("json")
    end
  end

  describe "#process_instances" do
    it "accumulates repeated collection, import, and export blocks" do
      input = [
        { collections: { name: { string: "c1" }, includes: [{ string: "x" }] } },
        { collections: { name: { string: "c2" }, includes: [{ string: "y" }] } },
        { imports: [{ format_type: "xml", file: "a.xml" }] },
        { imports: [{ format_type: "csv", file: "b.csv" }] },
        { exports: [{ format_type: "xml" }] },
        { exports: [{ format_type: "step" }] }
      ]

      result = processor.process_instances(input)

      expect(result[:collections].map { |c| c[:name] }).to eq(%w[c1 c2])
      expect(result[:imports].map { |i| i[:file] }).to eq(%w[a.xml b.csv])
      expect(result[:exports].map { |e| e[:format_type] }).to eq(%w[xml step])
    end
  end

  describe "ViewProcessing" do
    describe "#process_show_list" do
      it "extracts entity names from array of hashes" do
        result = processor.process_show_list([{ entity_name: "Foo" }, { entity_name: "Bar" }])
        expect(result).to eq(["Foo", "Bar"])
      end

      it "handles single entity name" do
        result = processor.process_show_list({ entity_name: "Baz" })
        expect(result).to eq(["Baz"])
      end
    end

    describe "#process_hide_list" do
      it "extracts entity names from array" do
        result = processor.process_hide_list([{ entity_name: "Secret" }])
        expect(result).to eq(["Secret"])
      end
    end
  end
end
