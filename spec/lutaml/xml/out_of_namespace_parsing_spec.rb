# frozen_string_literal: true

require "spec_helper"

# lutaml-model#754: parsing a document whose elements live in a namespace
# different from the model's bound namespace must not silently drop
# element content. The document's own namespace is adopted as an implicit
# alias of the model's namespace for the duration of the parse, so
# lenient (out-of-namespace) parsing is lossless for element content the
# way in-namespace parsing is.
module OutOfNamespaceParsingSpec
  class Gml32 < Lutaml::Xml::Namespace
    uri "http://www.opengis.net/gml/3.2"
    prefix_default "gml"
  end

  class Code < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      root "name"
      namespace Gml32
      map_content to: :value
    end
  end

  class EntryDefinition < Lutaml::Model::Serializable
    attribute :description, :string
    attribute :name, Code, collection: true

    xml do
      element "Definition"
      namespace Gml32
      map_element "description", to: :description
      map_element "name", to: :name
    end
  end

  class DictionaryEntry < Lutaml::Model::Serializable
    attribute :definition, EntryDefinition

    xml do
      element "dictionaryEntry"
      namespace Gml32
      map_element "Definition", to: :definition
    end
  end

  class Dictionary < Lutaml::Model::Serializable
    attribute :name, Code, collection: true
    attribute :dictionary_entry, DictionaryEntry, collection: true

    xml do
      element "Dictionary"
      namespace Gml32
      map_element "name", to: :name
      map_element "dictionaryEntry", to: :dictionary_entry
    end
  end

  def self.gml_doc(uri)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <gml:Dictionary xmlns:gml="#{uri}">
        <gml:name>codes</gml:name>
        <gml:dictionaryEntry>
          <gml:Definition>
            <gml:description>first</gml:description>
            <gml:name>ONE</gml:name>
          </gml:Definition>
        </gml:dictionaryEntry>
      </gml:Dictionary>
    XML
  end
end

RSpec.describe "out-of-namespace document parsing" do
  let(:in_namespace_xml) { OutOfNamespaceParsingSpec.gml_doc("http://www.opengis.net/gml/3.2") }
  let(:out_of_namespace_xml) { OutOfNamespaceParsingSpec.gml_doc("http://www.opengis.net/gml") }

  it "parses simple-type element content from a document in the bound namespace" do
    definition = OutOfNamespaceParsingSpec::Dictionary
      .from_xml(in_namespace_xml).dictionary_entry.first.definition
    expect(definition.description).to eq("first")
  end

  it "keeps simple-type element content when the document namespace differs (#754)" do
    definition = OutOfNamespaceParsingSpec::Dictionary
      .from_xml(out_of_namespace_xml).dictionary_entry.first.definition
    expect(definition.description).to eq("first")
  end

  it "keeps serializable-typed element content when the document namespace differs" do
    definition = OutOfNamespaceParsingSpec::Dictionary
      .from_xml(out_of_namespace_xml).dictionary_entry.first.definition
    expect(definition.name.map(&:value)).to eq(["ONE"])
  end

  it "keeps simple-type content at the document root level" do
    dictionary = OutOfNamespaceParsingSpec::Dictionary.from_xml(out_of_namespace_xml)
    expect(dictionary.name.map(&:value)).to eq(["codes"])
  end

  it "does not adopt an unrelated child namespace" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <gml:Dictionary xmlns:gml="http://www.opengis.net/gml"
                      xmlns:city="http://www.opengis.net/citygml/2.0">
        <city:name>not mine</city:name>
      </gml:Dictionary>
    XML
    dictionary = OutOfNamespaceParsingSpec::Dictionary.from_xml(xml)
    expect(dictionary.name).to be_empty
  end

  it "round-trips out-of-namespace content without losing the description" do
    dictionary = OutOfNamespaceParsingSpec::Dictionary.from_xml(out_of_namespace_xml)
    output = dictionary.to_xml(prefix: true)
    expect(output).to include("first")
    reparsed = OutOfNamespaceParsingSpec::Dictionary.from_xml(output)
    expect(reparsed.dictionary_entry.first.definition.description).to eq("first")
  end
end
