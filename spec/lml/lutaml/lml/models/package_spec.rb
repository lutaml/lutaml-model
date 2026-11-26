# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::Package do
  describe "attribute definitions" do
    it "has name attribute" do
      pkg = described_class.new(name: "Core")
      expect(pkg.name).to eq("Core")
    end

    it "has default visibility" do
      pkg = described_class.new
      expect(pkg.visibility).to eq("public")
    end

    it "has empty collections by default" do
      pkg = described_class.new
      expect(pkg.classes).to eq([])
      expect(pkg.enums).to eq([])
      expect(pkg.data_types).to eq([])
      expect(pkg.packages).to eq([])
    end
  end
end
