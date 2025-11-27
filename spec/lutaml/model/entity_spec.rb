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

    let(:entity_name) { Lutaml::Model::Xml::Element::NAME_ENTITY }
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
        if adapter_class == nokogiri_adapter
          expect(parsed.element_order.count(&:entity?)).to eq(2)
          expect(parsed.element_order.map(&:name)).to include(entity_name)
        else
          expect(parsed.element_order.count(&:entity?)).to eq(0)
          expect(parsed.element_order.map(&:name)).not_to include(entity_name)
        end
      end

      it "round-trips XML without affecting Ox/Oga behavior" do
        case adapter_class
        when nokogiri_adapter
          expect(serialized).to include("&mdash;", "&reg;")
        when oga_adapter
          # TODO: Oga currently skips named entities like &mdash; and &reg; while
          # parsing mixed content, so serialized XML lacks their literal forms.
          # See https://github.com/lutaml/moxml/issues/48
          # expect(serialized).to include("&mdash;", "&reg;")
        when ox_adapter
          expect(serialized).to include("—", "®")
        end
      end
    end

    context "with ordered: true root" do
      let(:xml) do
        <<~XML.strip
          <OrderedEntityArticle><headline>Launch</headline>&spacer;<description>Done</description>&spacer;</OrderedEntityArticle>
        XML
      end

      let(:parsed) { EntitySamples::OrderedRoot.from_xml(xml) }
      let(:serialized) { parsed.to_xml }

      it "keeps entity markers when rebuilding ordered elements" do
        case adapter_class
        when nokogiri_adapter
          expect(parsed.element_order.count(&:entity?)).to eq(2)
          expect(serialized).to include("&spacer;")
        when oga_adapter
          expect(parsed.element_order.count(&:entity?)).to eq(0)
          # TODO: Oga skips &spacer; nodes while parsing ordered content, so the
          # serialized XML currently lacks the literal entity.
          # See https://github.com/lutaml/moxml/issues/48
          # expect(serialized).to include("&spacer;")
        when ox_adapter
          expect(parsed.element_order.count(&:entity?)).to eq(0)
          expect(serialized).to include("\u00A0")
        end
      end
    end

    context "with default root options" do
      let(:xml) do
        <<~XML.strip
          <PlainEntityArticle>Budget&approx;Plan</PlainEntityArticle>
        XML
      end

      let(:parsed) { EntitySamples::PlainRoot.from_xml(xml) }
      let(:serialized) { parsed.to_xml }

      it "records standalone entity nodes" do
        case adapter_class
        when nokogiri_adapter
          expect(parsed.element_order.count(&:entity?)).to eq(1)
          expect(serialized).to include("&approx;")
        when oga_adapter
          expect(parsed.element_order.count(&:entity?)).to eq(0)
          # TODO: Oga currently skips &approx; during parsing, so the serialized
          # XML never receives the literal entity reference.
          # See https://github.com/lutaml/moxml/issues/48
          # expect(serialized).to include("&approx;")
        when ox_adapter
          expect(parsed.element_order.count(&:entity?)).to eq(0)
          expect(serialized).to include("≈")
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
