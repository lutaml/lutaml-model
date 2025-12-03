require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml_adapter/nokogiri_adapter"

# Bug #8: Namespace Prefix Missing on First Element in Chain
#
# SYMPTOM: When an element is the first to use a namespace in a document branch,
# it loses its namespace prefix on serialization. Nested elements also lose their prefixes.
#
# EXAMPLE:
#   Input:  <article xmlns:oasis="..."><table-wrap><oasis:table>...</oasis:table></table-wrap></article>
#   Output: <article xmlns:oasis="..."><table-wrap><table>...</table></table-wrap></article>
#                                                    ^^^^^ PREFIX MISSING!
#
# ROOT CAUSE: The prefix is not being applied to elements during serialization even though:
# - The namespace declaration is correctly placed at root
# - The DeclarationPlanner correctly identifies the namespace as used
# - The element mapping has the correct namespace configuration

module NamespaceBug8
  # Define a namespace for OASIS table elements
  class OasisNamespace < Lutaml::Model::XmlNamespace
    uri "http://www.niso.org/standards/z39-96/ns/oasis-exchange/table"
    prefix_default "oasis"
  end

  # Table element - first element to use oasis namespace
  class Table < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :content, :string

    xml do
      element "table"
      namespace OasisNamespace

      map_attribute "id", to: :id
      map_element "content", to: :content
    end
  end

  # Wrapper element - no namespace
  class TableWrap < Lutaml::Model::Serializable
    attribute :table, Table

    xml do
      element "table-wrap"
      map_element "table", to: :table
    end
  end

  # Root element with namespace scope
  class Article < Lutaml::Model::Serializable
    attribute :table_wrap, TableWrap

    xml do
      element "article"
      namespace_scope [OasisNamespace]
      map_element "table-wrap", to: :table_wrap
    end
  end
end

RSpec.describe "Bug #8: Namespace Prefix Missing on First Element" do
  let(:table) { NamespaceBug8::Table.new(id: "t1", content: "Cell") }
  let(:wrap) { NamespaceBug8::TableWrap.new(table: table) }
  let(:article) { NamespaceBug8::Article.new(table_wrap: wrap) }

  describe "serialization" do
    it "applies namespace prefix to first element using that namespace" do
      xml = article.to_xml

      # Should have oasis namespace declaration at root
      expect(xml).to include('xmlns:oasis="http://www.niso.org/standards/z39-96/ns/oasis-exchange/table"')

      # CRITICAL: Table element MUST have oasis: prefix
      expect(xml).to include("<oasis:table")
      expect(xml).to include("</oasis:table>")

      # Should NOT have unprefixed table element
      expect(xml).not_to match(/<table[^-]/)  # <table but not <table-wrap
    end

    it "preserves prefix through round-trip serialization" do
      xml = article.to_xml
      parsed = NamespaceBug8::Article.from_xml(xml)
      xml2 = parsed.to_xml

      # Prefix should be present in both serializations
      expect(xml).to include("<oasis:table")
      expect(xml2).to include("<oasis:table")
    end
  end

  describe "deserialization" do
    let(:input_xml) do
      <<~XML
        <article xmlns:oasis="http://www.niso.org/standards/z39-96/ns/oasis-exchange/table">
          <table-wrap>
            <oasis:table id="t1">
              <content>Cell</content>
            </oasis:table>
          </table-wrap>
        </article>
      XML
    end

    it "correctly parses prefixed elements" do
      parsed = NamespaceBug8::Article.from_xml(input_xml)

      expect(parsed.table_wrap).not_to be_nil
      expect(parsed.table_wrap.table).not_to be_nil
      expect(parsed.table_wrap.table.id).to eq("t1")
      expect(parsed.table_wrap.table.content).to eq("Cell")
    end
  end

  describe "nested elements in same namespace" do
    module NamespaceBug8Nested
      # Nested table element
      class Entry < Lutaml::Model::Serializable
        attribute :text, :string

        xml do
          element "entry"
          namespace NamespaceBug8::OasisNamespace
          map_element "text", to: :text
        end
      end

      class Row < Lutaml::Model::Serializable
        attribute :entry, Entry

        xml do
          element "row"
          namespace NamespaceBug8::OasisNamespace
          map_element "entry", to: :entry
        end
      end

      class TableNested < Lutaml::Model::Serializable
        attribute :row, Row

        xml do
          element "table"
          namespace NamespaceBug8::OasisNamespace
          map_element "row", to: :row
        end
      end

      class Article < Lutaml::Model::Serializable
        attribute :table, TableNested

        xml do
          element "article"
          namespace_scope [NamespaceBug8::OasisNamespace]
          map_element "table", to: :table
        end
      end
    end

    it "applies prefix to all nested elements in same namespace" do
      entry = NamespaceBug8Nested::Entry.new(text: "Cell")
      row = NamespaceBug8Nested::Row.new(entry: entry)
      table = NamespaceBug8Nested::TableNested.new(row: row)
      article = NamespaceBug8Nested::Article.new(table: table)

      xml = article.to_xml

      # All elements should have oasis: prefix
      expect(xml).to include("<oasis:table")
      expect(xml).to include("<oasis:row")
      expect(xml).to include("<oasis:entry")
      expect(xml).to include("</oasis:entry>")
      expect(xml).to include("</oasis:row>")
      expect(xml).to include("</oasis:table>")
    end
  end
end