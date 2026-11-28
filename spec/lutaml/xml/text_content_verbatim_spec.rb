# frozen_string_literal: true

require "spec_helper"

# lutaml-model#1249: text content emission must pass verbatim payloads
# through — a value that begins with an embedded XML declaration keeps
# its original declaration spelling (rfc8794's <sourcecode> carries an
# escaped XML example). moxml 0.6.23 fixed preprocess_entities to skip
# the declared-encoding rewrite outside document-parse entry
# (lutaml/moxml#604); the gemspec floors moxml at that version.
RSpec.describe "verbatim text content emission (#1249)" do
  let(:embedded_declaration) do
    %(<?xml version="1.0" encoding="utf-8"?>\n<EBMLSchema xmlns="urn:ietf:rfc:8794" version="1">\n</EBMLSchema>)
  end

  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string, collection: true

      xml do
        element "sourcecode"
        mixed_content
        map_content to: :content
      end
    end
  end

  it "keeps the declared encoding of an embedded declaration verbatim" do
    instance = model_class.new(content: [embedded_declaration])
    output = instance.to_xml

    aggregate_failures do
      expect(output).to include('encoding="utf-8"')
      expect(output).not_to include('encoding="UTF-8"')
    end
  end

  it "round-trips the payload through parse and serialize unchanged" do
    source = <<~XML
      <sourcecode>#{embedded_declaration.gsub('<', '&lt;').gsub('>', '&gt;')}</sourcecode>
    XML

    parsed = model_class.from_xml(source)
    output = parsed.to_xml

    aggregate_failures do
      expect(parsed.content.first).to eq(embedded_declaration)
      expect(output).to include('encoding="utf-8"')
    end
  end
end
