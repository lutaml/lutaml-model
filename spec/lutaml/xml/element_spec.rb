# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Xml::Element do
  it "does not treat regular element names as text content" do
    element = described_class.new("Element", "paragraph")

    expect(element).to be_element
    expect(element.element_tag).to eq("paragraph")
    expect(element.text_content).to be_nil
  end

  it "keeps legacy text nodes readable as text content" do
    element = described_class.new("Text", "content")

    expect(element).to be_text
    expect(element.text_content).to eq("content")
  end

  it "keeps legacy CDATA nodes readable as text content" do
    element = described_class.new("Text", "#cdata-section",
                                  text_content: "content")

    expect(element).to be_cdata
    expect(element.text_content).to eq("content")
  end
end
