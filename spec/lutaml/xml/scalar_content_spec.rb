# frozen_string_literal: true

require "spec_helper"

# A non-collection map_content attribute holds one String. XmlElement#text
# returns the list of text nodes once an element has more than one child node,
# so unmapped children between text pieces used to leave an Array in a String
# attribute (mml 2.4.7 Annotation#value for `a<span/>b`). The scalar is now the
# text nodes joined in document order; a collection attribute keeps the list.
RSpec.describe "map_content into a single-valued attribute" do
  let(:scalar_class) do
    Class.new(Lutaml::Model::Serializable) do
      def self.name = "ScalarContentSpec::Scalar"
      attribute :value, :string
      attribute :id, :string
      xml do
        root "x"
        map_attribute "id", to: :id
        map_content to: :value
      end
    end
  end

  let(:collection_class) do
    Class.new(Lutaml::Model::Serializable) do
      def self.name = "ScalarContentSpec::Collection"
      attribute :value, :string, collection: true
      xml do
        root "x"
        map_content to: :value
      end
    end
  end

  adapters = %i[nokogiri leptris ox]

  # input, scalar value, collection value (the collection keeps one entry per text node)
  [
    ["<x>ab</x>", "ab", ["ab"]],
    ["<x>a<span/>b</x>", "ab", %w[a b]],
    ["<x> a <span/> b </x>", " a  b ", [" a ", " b "]],
    ["<x>\n  <span/>\n</x>", "\n  \n", ["\n  ", "\n"]],
    ["<x>a<span>t</span>b</x>", "ab", %w[a b]],
    ["<x>a<span/>b<span/>c</x>", "abc", %w[a b c]],
    ["<x><span/></x>", "", nil],
    ["<x></x>", "", [""]],
    ["<x/>", "", [""]],
    ["<x><![CDATA[c]]></x>", "", nil],
    ["<x>a<![CDATA[c]]>b</x>", "ab", nil],
  ].each do |xml, scalar, collection|
    adapters.each do |adapter|
      it "reads #{xml.inspect} as #{scalar.inspect} (#{adapter})" do
        skip "ox drops whitespace-only text before the model sees it" if adapter == :ox && xml.include?("\n")

        Lutaml::Model::Config.with_adapter(xml: adapter) do
          value = scalar_class.from_xml(xml).value
          expect(value).to eq(scalar)
          expect(value).to be_a(String)
        end
      end

      next if collection.nil?

      it "keeps the collection of #{xml.inspect} as #{collection.inspect} (#{adapter})" do
        next unless adapter == :nokogiri # collection shape is pinned on the primary adapter only

        Lutaml::Model::Config.with_adapter(xml: adapter) do
          expect(collection_class.from_xml(xml).value).to eq(collection)
        end
      end
    end
  end

  it "still reads the sibling attribute next to scattered text" do
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      record = scalar_class.from_xml('<x id="7">a<span/>b</x>')
      expect([record.id, record.value]).to eq(["7", "ab"])
    end
  end
end
