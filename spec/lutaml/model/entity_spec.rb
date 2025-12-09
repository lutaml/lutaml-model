# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"

module EntitySamples
  class MixedRoot < Lutaml::Model::Serializable
    attribute :content, :string
    attribute :emphasis, :string

    xml do
      root "MixedEntityArticle", mixed: true

      map_content to: :content
      map_element :em, to: :emphasis
    end
  end

  class OrderedRoot < Lutaml::Model::Serializable
    attribute :headline, :string
    attribute :description, :string
    attribute :content, :string

    xml do
      root "OrderedEntityArticle", ordered: true

      map_element :headline, to: :headline
      map_content to: :content
      map_element :description, to: :description
    end
  end

  class PlainRoot < Lutaml::Model::Serializable
    attribute :body, :string

    xml do
      root "PlainEntityArticle"

      map_content to: :body
    end
  end
end

RSpec.describe "XMLEntityHandling" do
  shared_examples "entity-aware serialization" do |adapter_class|
    around do |example|
      original_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = original_adapter
    end

    let(:nokogiri_adapter) { Lutaml::Model::Xml::NokogiriAdapter }
    let(:oga_adapter) { Lutaml::Model::Xml::OgaAdapter }
    let(:ox_adapter) { Lutaml::Model::Xml::OxAdapter }

    context "with mixed: true root" do
      let(:xml) do
        <<~XML.strip
          <MixedEntityArticle>Intro&mdash;<em>Focus</em>&reg;Tail</MixedEntityArticle>
        XML
      end

      let(:parsed) { EntitySamples::MixedRoot.from_xml(xml) }
      let(:serialized) { parsed.to_xml }

      it "tracks entity references in element_order" do
        expect(parsed.element_order.map(&:name)).to include("text", "em")
      end

      it "round-trips XML without affecting Ox/Oga behavior" do
        if adapter_class == oga_adapter
          # TODO: Oga currently skips named entities like &mdash; and &reg; while
          # parsing mixed content, so serialized XML lacks their literal forms.
          # See https://github.com/lutaml/moxml/issues/48
          # expect(serialized).to include("&mdash;", "&reg;")
        else
          expect(serialized).to include("—", "®")
        end
      end
    end

    context "with ordered: true root" do
      let(:xml) do
        <<~XML.strip
          <OrderedEntityArticle><headline>Launch</headline>&nbsp;<description>Done</description>&nbsp;</OrderedEntityArticle>
        XML
      end

      let(:parsed) { EntitySamples::OrderedRoot.from_xml(xml) }
      let(:serialized) { parsed.to_xml }

      it "keeps entity markers when rebuilding ordered elements" do
        if adapter_class == oga_adapter
          # TODO: Oga skips &nbsp; nodes while parsing ordered content, so the
          # serialized XML currently lacks the literal entity.
          # See https://github.com/lutaml/moxml/issues/48
          # expect(serialized).to include("&nbsp;")
        else
          expect(serialized).to include("\u00A0")
        end
      end
    end

    context "with default root options" do
      let(:xml) do
        <<~XML.strip
          <PlainEntityArticle>Budget&ap;Plan</PlainEntityArticle>
        XML
      end

      let(:parsed) { EntitySamples::PlainRoot.from_xml(xml) }
      let(:serialized) { parsed.to_xml }

      it "records standalone entity nodes" do
        if adapter_class == oga_adapter
          # TODO: Oga currently skips &approx; during parsing, so the serialized
          # XML never receives the literal entity reference.
          # See https://github.com/lutaml/moxml/issues/48
          # expect(serialized).to include("&approx;")
        elsif adapter_class == nokogiri_adapter
          expect(serialized).to include("≈")
        else
          expect(serialized).to include("&amp;ap;")
        end
      end
    end
  end

  describe Lutaml::Model::Xml::NokogiriAdapter do
    it_behaves_like "entity-aware serialization", described_class
  end

  describe Lutaml::Model::Xml::OgaAdapter do
    it_behaves_like "entity-aware serialization", described_class
  end

  describe Lutaml::Model::Xml::OxAdapter do
    it_behaves_like "entity-aware serialization", described_class
  end
end
