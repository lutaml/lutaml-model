# frozen_string_literal: true

require "spec_helper"
require "nokogiri"
require "lutaml/model"
require "lutaml/xml"
require "lutaml/xml/adapter/nokogiri_adapter"

# Regression tests for lutaml-model#871.
#
# libxml2 (the Nokogiri backend) caps its input buffer at 10 MB. Parsing a
# longer document in recover mode records a FATAL "Resource limit exceeded:
# Buffer size limit exceeded, try XML_PARSE_HUGE" error on the document and
# returns the partial tree, so every node past the cap silently vanishes.
# XmlParser now refuses documents whose parse_errors carry a fatal error
# instead of deserializing the truncated input.
RSpec.describe "recovered fatal parse errors" do
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

  it "hits the libxml2 buffer cap in recover mode past 10 MB" do
    errors = Nokogiri::XML(over_cap_document) { |config| config.recover.nonet }.errors

    expect(errors.map(&:message).join("\n")).to match(/\bFATAL:/)
  end

  it "raises instead of silently truncating on the nokogiri path" do
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      expect { root_class.from_xml(over_cap_document) }
        .to raise_error(Lutaml::Model::InvalidFormatError, /resource limit.*truncated/m)
    end
  end

  it "raises from the adapter layer directly" do
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      expect { Lutaml::Xml::Adapter::NokogiriAdapter.parse(over_cap_document) }
        .to raise_error(Lutaml::Model::InvalidFormatError, /XML_PARSE_HUGE/)
    end
  end

  it "keeps parsing documents whose fatals do not drop content" do
    xml = "  <?xml version=\"1.0\"?>\n<metanorma><annex id=\"a\"/></metanorma>"

    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      model = root_class.from_xml(xml)

      expect(model.annexes.map(&:id)).to eq(["a"])
    end
  end

  it "still parses smaller documents without any fatal-error handling" do
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      model = root_class.from_xml(
        build_document(chunk_count: 2, chunk_size: 500_000, with_tail: true),
      )

      expect(model.annexes.map(&:id))
        .to eq(["annex0", "annex1", "annex-tail-marker"])
    end
  end
end
