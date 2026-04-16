# frozen_string_literal: true

require "spec_helper"

# Conformance tests for W3C XML Namespaces 1.0
# @see https://www.w3.org/TR/xml-names/
#
# Each test references a specific section of the specification.
# Requirement IDs follow the pattern NS-<section>-<number>.
RSpec.describe "XML Namespaces 1.0 Conformance" do
  after do
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  # ── Section 2: Declaring Namespaces ──────────────────────────────────

  describe "NS-2: Namespace declarations" do
    let(:default_ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://default.ns"
      end
    end

    let(:prefixed_ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.ns"
        prefix_default "ex"
      end
    end

    # NS-2-1: Default namespace declaration (xmlns="...")
    it "NS-2-1: supports default namespace declaration" do
      ns = default_ns
      stub_const("NsDefaultModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "doc"
          namespace ns
          map_content to: :content
        end
      end)

      model = NsDefaultModel.new(content: "text")
      xml = model.to_xml

      expect(xml).to include('xmlns="http://default.ns"')
    end

    # NS-2-2: Prefixed namespace declaration (xmlns:prefix="...")
    it "NS-2-2: supports prefixed namespace in parsing and round-trip" do
      ns = prefixed_ns
      stub_const("NsPrefixedModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "doc"
          namespace ns
          map_content to: :content
        end
      end)

      # Parse prefixed XML
      xml_in = '<ex:doc xmlns:ex="http://example.ns">text</ex:doc>'
      model = NsPrefixedModel.from_xml(xml_in)
      expect(model.content).to eq("text")

      # Serialization uses namespace form (default or prefixed)
      xml_out = model.to_xml
      expect(xml_out).to include("http://example.ns")
    end

    # NS-2-3: Round-trip preserves namespace declarations
    it "NS-2-3: preserves namespace declarations in round-trip" do
      ns = default_ns
      stub_const("NsRoundTripModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "doc"
          namespace ns
          map_content to: :content
        end
      end)

      xml_in = '<doc xmlns="http://default.ns">text</doc>'
      model = NsRoundTripModel.from_xml(xml_in)
      xml_out = model.to_xml

      expect(xml_out).to include('xmlns="http://default.ns"')
      expect(model.content).to eq("text")
    end
  end

  # ── Section 5.2: Element Default Namespace ────────────────────────────

  describe "NS-5.2: Element default namespace" do
    let(:parent_ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://parent.ns"
      end
    end

    # NS-5.2-1: Default namespace applies to the element it is declared on
    it "NS-5.2-1: default namespace applies to declaring element" do
      ns = parent_ns
      stub_const("NsParentElemModel", Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "parent"
          namespace ns
          map_content to: :text
        end
      end)

      model = NsParentElemModel.new(text: "hello")
      xml = model.to_xml

      expect(xml).to include('xmlns="http://parent.ns"')
    end

    # NS-5.2-2: Unprefixed attributes are NOT in any namespace
    it "NS-5.2-2: unprefixed attributes have no namespace even with default namespace" do
      ns = parent_ns
      stub_const("AttrWithDefaultNsModel", Class.new(Lutaml::Model::Serializable) do
        attribute :kind, :string
        attribute :content, :string

        xml do
          element "item"
          namespace ns
          map_attribute "kind", to: :kind
          map_content to: :content
        end
      end)

      xml_in = '<item xmlns="http://parent.ns" kind="special">text</item>'
      model = AttrWithDefaultNsModel.from_xml(xml_in)

      expect(model.kind).to eq("special")
      xml_out = model.to_xml
      # Attribute "kind" should NOT be prefixed with namespace
      expect(xml_out).to include('kind="special"')
      expect(xml_out).not_to include("xmlns:kind")
    end
  end

  # ── Section 5.3: Prefixed Names ──────────────────────────────────────

  describe "NS-5.3: Prefixed names" do
    let(:ex_ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.ns"
        prefix_default "ex"
      end
    end

    # NS-5.3-1: Prefixed element names include namespace prefix
    it "NS-5.3-1: parses prefixed element names correctly" do
      ns = ex_ns
      stub_const("PrefixedNsModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "doc"
          namespace ns
          map_content to: :content
        end
      end)

      xml_in = '<ex:doc xmlns:ex="http://example.ns">data</ex:doc>'
      model = PrefixedNsModel.from_xml(xml_in)
      expect(model.content).to eq("data")

      # Namespace is preserved in output
      xml_out = model.to_xml
      expect(xml_out).to include("http://example.ns")
    end

    # NS-5.3-2: Prefixed element round-trip
    it "NS-5.3-2: preserves prefixed element in round-trip" do
      ns = ex_ns
      stub_const("PrefixedNsRoundModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "doc"
          namespace ns
          map_content to: :content
        end
      end)

      xml_in = '<ex:doc xmlns:ex="http://example.ns">data</ex:doc>'
      model = PrefixedNsRoundModel.from_xml(xml_in)
      xml_out = model.to_xml

      expect(model.content).to eq("data")
      expect(xml_out).to include("ex:doc")
    end
  end

  # ── Section 6: Namespace Scope ───────────────────────────────────────

  describe "NS-6: Namespace scope" do
    let(:parent_ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://parent.ns"
      end
    end

    let(:child_ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://child.ns"
      end
    end

    # NS-6-1: Namespace declaration scope includes descendants
    it "NS-6-1: namespace scope applies to descendant elements" do
      ns = parent_ns
      stub_const("NsScopeChildModel", Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "child"
          map_content to: :text
        end
      end)

      stub_const("NsScopeParentModel", Class.new(Lutaml::Model::Serializable) do
        attribute :child, NsScopeChildModel

        xml do
          element "parent"
          namespace ns
          map_element "child", to: :child
        end
      end)

      child = NsScopeChildModel.new(text: "nested")
      model = NsScopeParentModel.new(child: child)
      xml = model.to_xml

      expect(xml).to include('xmlns="http://parent.ns"')
    end

    # NS-6-2: Inner declarations override outer
    it "NS-6-2: inner namespace declarations override outer ones" do
      p_ns = parent_ns
      c_ns = child_ns
      stub_const("NsOverrideChildModel2", Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "child"
          namespace c_ns
          map_content to: :text
        end
      end)

      stub_const("NsOverrideParentModel2", Class.new(Lutaml::Model::Serializable) do
        attribute :child, NsOverrideChildModel2

        xml do
          element "parent"
          namespace p_ns
          map_element "child", to: :child
        end
      end)

      child = NsOverrideChildModel2.new(text: "nested")
      model = NsOverrideParentModel2.new(child: child)
      xml = model.to_xml

      expect(xml).to include("http://parent.ns")
      expect(xml).to include("http://child.ns")
    end

    # NS-6-3: Undeclaring default namespace with xmlns=""
    it "NS-6-3: supports undeclaring default namespace" do
      stub_const("NsUndeclaredModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "doc"
          map_content to: :content
        end
      end)

      model = NsUndeclaredModel.from_xml('<doc xmlns="">text</doc>')

      expect(model.content).to eq("text")
      xml_out = model.to_xml
      # Should NOT have a namespace
      expect(xml_out).not_to include("http://parent.ns")
    end
  end

  # ── Section 7: Reserved Prefix xml ───────────────────────────────────

  describe "NS-7: Reserved prefix 'xml'" do
    # NS-7-1: The xml prefix is bound to http://www.w3.org/XML/1998/namespace
    it "NS-7-1: xml prefix is implicitly bound (never needs declaration)" do
      stub_const("XmlReservedModel", Class.new(Lutaml::Model::Serializable) do
        attribute :lang, Lutaml::Xml::W3c::XmlLangType
        attribute :content, :string

        xml do
          element "doc"
          map_attribute "lang", to: :lang
          map_content to: :content
        end
      end)

      model = XmlReservedModel.new(lang: "en", content: "hello")
      xml = model.to_xml

      expect(xml).to include('xml:lang="en"')
      # Must NOT declare xmlns:xml
      expect(xml).not_to include("xmlns:xml=")
    end

    # NS-7-2: xml prefix with case-insensitive variants
    it "NS-7-2: recognizes xml: attributes in round-trip" do
      stub_const("XmlCaseModel", Class.new(Lutaml::Model::Serializable) do
        attribute :lang, Lutaml::Xml::W3c::XmlLangType
        attribute :content, :string

        xml do
          element "p"
          map_attribute "lang", to: :lang
          map_content to: :content
        end
      end)

      xml_in = '<p xml:lang="en">hello</p>'
      model = XmlCaseModel.from_xml(xml_in)
      expect(model.lang).to eq("en")

      xml_out = model.to_xml
      expect(xml_out).to include('xml:lang="en"')
      expect(xml_out).not_to include("xmlns:xml=")
    end

    # NS-7-3: User cannot redefine xml prefix to a different URI
    it "NS-7-3: warns when redefining reserved xml prefix" do
      warnings = []
      allow(Lutaml::Model::Logger).to receive(:warn) do |msg, _path|
        warnings << msg
      end

      klass = Class.new(Lutaml::Xml::Namespace) do
        uri "http://example.com/ns"
        prefix_default "xml"
      end

      # Warning fires on instantiation
      klass.new

      expect(warnings.any? { |w| w.include?("W3C-reserved") }).to be true
    end

    # NS-7-4: xmlns prefix is reserved for namespace declarations
    it "NS-7-4: xmlns is reserved and cannot be used as a prefix" do
      xml = '<root xmlns:xmlns="http://example.com/"/>'
      doc = Nokogiri::XML(xml)
      expect(doc.errors.any? { |e| e.message.include?("xmlns") }).to be true
    end
  end

  # ── Section 6.1: Multiple Namespace Declarations ─────────────────────

  describe "NS-6.1: Multiple namespace declarations" do
    let(:parent_ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://parent.ns"
        prefix_default "p"
      end
    end

    let(:child_ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "http://child.ns"
        prefix_default "c"
      end
    end

    # NS-6.1-1: Multiple prefixed namespaces on different elements
    it "NS-6.1-1: supports multiple namespace declarations" do
      p_ns = parent_ns
      c_ns = child_ns

      stub_const("MultiNsChildModel", Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "child"
          namespace c_ns
          map_content to: :text
        end
      end)

      stub_const("MultiNsParentModel", Class.new(Lutaml::Model::Serializable) do
        attribute :child, MultiNsChildModel

        xml do
          element "parent"
          namespace p_ns
          map_element "child", to: :child
        end
      end)

      child = MultiNsChildModel.new(text: "data")
      model = MultiNsParentModel.new(child: child)
      xml = model.to_xml

      # Both namespaces appear in output
      expect(xml).to include("http://parent.ns")
      expect(xml).to include("http://child.ns")
    end

    # NS-6.1-2: Round-trip with multiple namespaces
    it "NS-6.1-2: preserves multiple namespaces in round-trip" do
      p_ns = parent_ns
      c_ns = child_ns

      stub_const("MultiNsChildRT", Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "child"
          namespace c_ns
          map_content to: :text
        end
      end)

      stub_const("MultiNsParentRT", Class.new(Lutaml::Model::Serializable) do
        attribute :child, MultiNsChildRT

        xml do
          element "parent"
          namespace p_ns
          map_element "child", to: :child
        end
      end)

      xml_in = '<p:parent xmlns:p="http://parent.ns"><c:child xmlns:c="http://child.ns">data</c:child></p:parent>'
      model = MultiNsParentRT.from_xml(xml_in)
      xml_out = model.to_xml

      expect(model.child.text).to eq("data")
      expect(xml_out).to include("http://parent.ns")
      expect(xml_out).to include("http://child.ns")
    end
  end

  # ── xml:lang, xml:space, xml:base, xml:id ────────────────────────────

  describe "XML 1.0 reserved attributes (xml:* family)" do
    # XML-ATTR-1: xml:lang identifies language
    it "XML-ATTR-1: supports xml:lang attribute" do
      stub_const("XmlLangModel", Class.new(Lutaml::Model::Serializable) do
        attribute :lang, Lutaml::Xml::W3c::XmlLangType
        attribute :content, :string

        xml do
          element "p"
          map_attribute "lang", to: :lang
          map_content to: :content
        end
      end)

      model = XmlLangModel.new(lang: "en-US", content: "Hello")
      xml = model.to_xml
      expect(xml).to include('xml:lang="en-US"')

      parsed = XmlLangModel.from_xml(xml)
      expect(parsed.lang).to eq("en-US")
    end

    # XML-ATTR-2: xml:space controls whitespace handling
    it "XML-ATTR-2: supports xml:space attribute" do
      stub_const("XmlSpaceModel", Class.new(Lutaml::Model::Serializable) do
        attribute :space, Lutaml::Xml::W3c::XmlSpaceType
        attribute :content, :string

        xml do
          element "pre"
          map_attribute "space", to: :space
          map_content to: :content
        end
      end)

      model = XmlSpaceModel.new(space: "preserve", content: "  indented  ")
      xml = model.to_xml
      expect(xml).to include('xml:space="preserve"')

      parsed = XmlSpaceModel.from_xml(xml)
      expect(parsed.space).to eq("preserve")
    end

    # XML-ATTR-3: xml:space rejects invalid values
    it "XML-ATTR-3: xml:space validates value is 'default' or 'preserve'" do
      expect do
        Lutaml::Xml::W3c::XmlSpaceType.cast("invalid")
      end.to raise_error(ArgumentError, /must be 'default' or 'preserve'/)
    end

    # XML-ATTR-4: xml:base sets base URI
    it "XML-ATTR-4: supports xml:base attribute" do
      stub_const("XmlBaseModel", Class.new(Lutaml::Model::Serializable) do
        attribute :base, Lutaml::Xml::W3c::XmlBaseType
        attribute :content, :string

        xml do
          element "a"
          map_attribute "base", to: :base
          map_content to: :content
        end
      end)

      model = XmlBaseModel.new(base: "http://example.com/", content: "Link")
      xml = model.to_xml
      expect(xml).to include('xml:base="http://example.com/"')

      parsed = XmlBaseModel.from_xml(xml)
      expect(parsed.base).to eq("http://example.com/")
    end

    # XML-ATTR-5: xml:id for unique identifiers
    it "XML-ATTR-5: supports xml:id attribute" do
      stub_const("XmlIdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :id, Lutaml::Xml::W3c::XmlIdType
        attribute :content, :string

        xml do
          element "section"
          map_attribute "id", to: :id
          map_content to: :content
        end
      end)

      model = XmlIdModel.new(id: "sec-1", content: "Introduction")
      xml = model.to_xml
      expect(xml).to include('xml:id="sec-1"')

      parsed = XmlIdModel.from_xml(xml)
      expect(parsed.id).to eq("sec-1")
    end

    # XML-ATTR-6: Multiple xml:* attributes on same element
    it "XML-ATTR-6: supports multiple xml:* attributes on same element" do
      stub_const("XmlMultiAttrModel", Class.new(Lutaml::Model::Serializable) do
        attribute :lang, Lutaml::Xml::W3c::XmlLangType
        attribute :space, Lutaml::Xml::W3c::XmlSpaceType
        attribute :id, Lutaml::Xml::W3c::XmlIdType
        attribute :content, :string

        xml do
          element "p"
          map_attribute "lang", to: :lang
          map_attribute "space", to: :space
          map_attribute "id", to: :id
          map_content to: :content
        end
      end)

      model = XmlMultiAttrModel.new(
        lang: "fr", space: "preserve", id: "p1", content: "Texte"
      )
      xml = model.to_xml

      expect(xml).to include('xml:lang="fr"')
      expect(xml).to include('xml:space="preserve"')
      expect(xml).to include('xml:id="p1"')
      # Must NOT declare xmlns:xml
      expect(xml).not_to include("xmlns:xml=")
    end
  end
end
