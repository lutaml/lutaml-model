# frozen_string_literal: true

require "spec_helper"

# lutaml-model#858: leptris hydrates :string values as ASCII-8BIT
# (FFI's :string return tag) while nokogiri returns UTF-8. Values are
# character data; both adapters must agree on the encoding.
RSpec.describe "leptris string encoding parity with nokogiri",
               if: defined?(Leptris::XML::Document) do
  let(:xml) do
    <<~XML
      <Relationship Id="rId5" Target="http://example.com/x"/>
    XML
  end

  let(:klass) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :target, :string

      xml do
        element "Relationship"
        map_attribute "Id", to: :id
        map_attribute "Target", to: :target
      end
    end
  end

  before do
    stub_const("LeptrisEncoding::Rel", klass)
  end

  it "hydrates attribute values as UTF-8" do
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      parsed = klass.from_xml(xml)
      expect(parsed.id.encoding).to eq(Encoding::UTF_8)
      expect(parsed.target.encoding).to eq(Encoding::UTF_8)
    end

    Lutaml::Model::Config.with_adapter(xml: :leptris) do
      parsed = klass.from_xml(xml)
      expect(parsed.id.encoding).to eq(Encoding::UTF_8)
      expect(parsed.target.encoding).to eq(Encoding::UTF_8)
    end
  end

  it "hydrates element text as UTF-8" do
    doc = "<Note>café – naïve</Note>"
    text_class = Class.new(Lutaml::Model::Serializable) do
      attribute :text, :string

      xml do
        element "Note"
        map_content to: :text
      end
    end
    stub_const("LeptrisEncoding::Note", text_class)

    Lutaml::Model::Config.with_adapter(xml: :leptris) do
      parsed = text_class.from_xml(doc)
      expect(parsed.text.encoding).to eq(Encoding::UTF_8)
      expect(parsed.text).to eq("café – naïve")
    end
  end
end
