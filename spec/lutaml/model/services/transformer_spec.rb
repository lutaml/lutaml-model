# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::Transformer do
  describe "open/closed principle" do
    it "defaults to import direction" do
      transformer = described_class.new(nil, nil)
      expect(transformer.export_direction?).to be false
    end

    it "ImportTransformer returns false for export_direction?" do
      transformer = Lutaml::Model::ImportTransformer.new(nil, nil)
      expect(transformer.export_direction?).to be false
    end

    it "ExportTransformer returns true for export_direction?" do
      transformer = Lutaml::Model::ExportTransformer.new(nil, nil)
      expect(transformer.export_direction?).to be true
    end

    it "allows custom subclass to define direction" do
      custom = Class.new(described_class) do
        def export_direction?
          true
        end
      end
      expect(custom.new(nil, nil).export_direction?).to be true
    end
  end

  describe "class-level .call" do
    it "ImportTransformer.call returns value unchanged without transforms" do
      result = Lutaml::Model::ImportTransformer.call("hello", nil, nil)
      expect(result).to eq("hello")
    end

    it "ExportTransformer.call returns value unchanged without transforms" do
      result = Lutaml::Model::ExportTransformer.call("hello", nil, nil)
      expect(result).to eq("hello")
    end
  end
end
