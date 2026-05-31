# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Line ending configuration" do
  before do
    test_class = Class.new do
      include Lutaml::Model::Serialize

      attribute :title, :string
      attribute :body, :string

      xml do
        element "article"
        map_element "title", to: :title
        map_element "body", to: :body
      end
    end

    stub_const("LineEndingArticle", test_class)
  end

  let(:model) { LineEndingArticle.new(title: "Test", body: "Content") }

  it "uses LF (\\n) line endings by default" do
    xml = model.to_xml
    expect(xml).not_to include("\r\n")
  end

  it "produces CRLF when line_ending: CRLF is specified" do
    xml = model.to_xml(line_ending: "\r\n")
    lines = xml.split("\n", -1)
    crlf_count = lines.count { |l| l.end_with?("\r") }
    expect(crlf_count).to be > 0
  end

  it "applies line endings consistently across declaration and body" do
    xml = model.to_xml(line_ending: "\r\n", declaration: true)
    expect(xml.lines).to all(end_with("\r\n"))
  end

  it "preserves LF in round-trip" do
    xml_in = "<article><title>Test</title><body>Content</body></article>"
    parsed = LineEndingArticle.from_xml(xml_in)
    xml_out = parsed.to_xml
    expect(xml_out).not_to include("\r\n")
  end

  it "does not produce mixed line endings" do
    xml = model.to_xml(line_ending: "\r\n")
    crlf_positions = []
    lf_only_positions = []
    xml.each_char.with_index do |c, i|
      next unless c == "\n"

      prev = i > 0 ? xml[i - 1] : nil
      if prev == "\r"
        crlf_positions << i
      else
        lf_only_positions << i
      end
    end
    # Either all newlines are CRLF or none are — no mixing
    expect(lf_only_positions).to be_empty, "Mixed line endings found"
  end
end
