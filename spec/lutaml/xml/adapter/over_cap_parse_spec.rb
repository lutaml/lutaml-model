# frozen_string_literal: true

require "spec_helper"
require "nokogiri"
require "lutaml/model"
require "lutaml/xml"
require "lutaml/xml/adapter/nokogiri_adapter"

# Regression coverage for lutaml-model#871: very large documents must
# deserialize completely, with no silent truncation and no data loss.
#
# libxml2's default mode caps its input buffer at 10 MB and, in recover
# mode, silently drops every node past the cap. moxml 0.5.84 always
# passes XML_PARSE_HUGE, so the Nokogiri path now parses past the cap.
# XmlParser additionally refuses recovered parses that report the
# resource-limit fatal family, which still protects moxml releases that
# truncate.
RSpec.describe "parsing documents past libxml2's 10 MB buffer cap" do
  let(:annex_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string

      xml do
        element "annex"
        map_attribute "id", to: :id
      end
    end
  end

  let(:root_class) do
    annex = annex_class

    Class.new(Lutaml::Model::Serializable) do
      attribute :annexes, annex, collection: true

      xml do
        element "metanorma"
        map_element "annex", to: :annexes
      end
    end
  end

  def build_document(chunk_count:, chunk_size:, with_tail: false)
    filler = "A" * chunk_size
    document = +"<metanorma>"
    chunk_count.times do |index|
      document << %(<annex id="annex#{index}" data="#{filler}"/>)
    end
    document << %(<annex id="annex-tail-marker"/>) if with_tail
    document << "</metanorma>"
    document
  end

  # Six 1.7 MB attribute values push the cumulative input past libxml2's
  # 10 MB buffer cap mid-document, mirroring the issue's failing manifest.
  def over_cap_document
    build_document(chunk_count: 6, chunk_size: 1_700_000, with_tail: true)
  end

  it "confirms libxml2's default mode still trips the buffer cap past 10 MB" do
    errors = Nokogiri::XML(over_cap_document) { |config| config.recover.nonet }.errors

    expect(errors.map(&:message).join("\n")).to match(/\bFATAL:/)
  end

  it "parses over-cap documents completely on the nokogiri path" do
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      model = root_class.from_xml(over_cap_document)

      expect(model.annexes.map(&:id)).to eq(
        ["annex0", "annex1", "annex2", "annex3", "annex4", "annex5",
         "annex-tail-marker"],
      )
    end
  end

  it "returns the complete tree from the adapter layer" do
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      document = Lutaml::Xml::Adapter::NokogiriAdapter.parse(over_cap_document)

      expect(document.root.children.count).to eq(7)
    end
  end

  it "keeps parsing documents whose fatals do not drop content" do
    xml = "  <?xml version=\"1.0\"?>\n<metanorma><annex id=\"a\"/></metanorma>"

    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      model = root_class.from_xml(xml)

      expect(model.annexes.map(&:id)).to eq(["a"])
    end
  end

  it "keeps parsing smaller documents unchanged" do
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      model = root_class.from_xml(
        build_document(chunk_count: 2, chunk_size: 500_000, with_tail: true),
      )

      expect(model.annexes.map(&:id))
        .to eq(["annex0", "annex1", "annex-tail-marker"])
    end
  end
end
