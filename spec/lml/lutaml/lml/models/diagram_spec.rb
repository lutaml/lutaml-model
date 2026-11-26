# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::Diagram do
  describe "attribute definitions" do
    it "has name attribute" do
      diagram = described_class.new(name: "SystemOverview")
      expect(diagram.name).to eq("SystemOverview")
    end

    it "has default visibility" do
      diagram = described_class.new
      expect(diagram.visibility).to eq("public")
    end
  end
end
