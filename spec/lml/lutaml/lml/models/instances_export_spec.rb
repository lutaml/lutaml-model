# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::InstancesExport do
  it "has format_type" do
    exp = described_class.new(format_type: "json")
    expect(exp.format_type).to eq("json")
  end

  it "has attributes collection defaulting to empty" do
    exp = described_class.new
    expect(exp.attributes).to eq([])
  end

  it "holds export attributes" do
    attr = Lutaml::Lml::TopElementAttribute.new(name: "file", value: "out.xml")
    exp = described_class.new(format_type: "xml", attributes: [attr])
    expect(exp.attributes.length).to eq(1)
    expect(exp.attributes.first.name).to eq("file")
  end
end
