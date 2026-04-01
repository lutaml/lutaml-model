# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"
require "lutaml/xml/adapter/nokogiri_adapter"
require "lutaml/xml/adapter/ox_adapter"
require "lutaml/xml/adapter/oga_adapter"

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

    let(:nokogiri_adapter) { Lutaml::Xml::Adapter::NokogiriAdapter }
    let(:oga_adapter) { Lutaml::Xml::Adapter::OgaAdapter }
    let(:ox_adapter) { Lutaml::Xml::Adapter::OxAdapter }

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
        serialized_utf8 = serialized.force_encoding("UTF-8")
        expect(serialized_utf8).to include("\u2014", "\u00AE")
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
        serialized_utf8 = serialized.force_encoding("UTF-8")
        expect(serialized_utf8).to include("\u00A0")
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
        if adapter_class == nokogiri_adapter || adapter_class == oga_adapter
          expect(serialized).to include("\u2248")
        else
          expect(serialized).to include("&amp;ap;")
        end
      end
    end
  end

  describe Lutaml::Xml::Adapter::NokogiriAdapter do
    it_behaves_like "entity-aware serialization", described_class
  end

  describe Lutaml::Xml::Adapter::OgaAdapter do
    it_behaves_like "entity-aware serialization", described_class
  end

  describe Lutaml::Xml::Adapter::OxAdapter do
    it_behaves_like "entity-aware serialization", described_class
  end
end
