# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::Collection do
  it "has name attribute" do
    coll = described_class.new(name: "test_suite")
    expect(coll.name).to eq("test_suite")
  end

  it "has includes collection" do
    coll = described_class.new(includes: ["item1", "item2"])
    expect(coll.includes).to eq(["item1", "item2"])
  end

  it "has validations collection" do
    coll = described_class.new(validations: ["count >= 3"])
    expect(coll.validations).to eq(["count >= 3"])
  end

  it "defaults to empty collections" do
    coll = described_class.new
    expect(coll.includes).to be_nil
    expect(coll.validations).to be_nil
  end
end
