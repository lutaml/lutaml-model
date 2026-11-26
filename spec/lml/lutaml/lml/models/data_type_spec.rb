# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::DataType do
  describe "attribute definitions" do
    it "has name attribute" do
      dt = described_class.new(name: "Uri")
      expect(dt.name).to eq("Uri")
    end

    it "has default keyword" do
      dt = described_class.new
      expect(dt.keyword).to eq("dataType")
    end

    it "has default visibility" do
      dt = described_class.new
      expect(dt.visibility).to eq("public")
    end

    it "has default is_abstract" do
      dt = described_class.new
      expect(dt.is_abstract).to eq(false)
    end
  end

  describe ".entity_type" do
    it "returns :data_types" do
      expect(described_class.entity_type).to eq(:data_types)
    end
  end
end
