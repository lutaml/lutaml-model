# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Namespace-Aware Round-Trip Serialization" do
  # OOXML-style namespaces for same-named elements
  let(:w14_namespace) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://schemas.microsoft.com/office/word/2010/wordml"
      prefix_default "w14"
      element_form_default :qualified
    end
  end

  let(:w15_namespace) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://schemas.microsoft.com/office/word/2012/wordml"
      prefix_default "w15"
      element_form_default :qualified
    end
  end

  let(:settings_namespace) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      prefix_default "w"
      element_form_default :qualified
    end
  end

  # W14 DocId - model with its own namespace
  let(:w14_doc_id_class) do
    ns = w14_namespace
    Class.new do
      include Lutaml::Model::Serialize

      attribute :val, :string

      xml do
        element "docId"
        namespace ns
        map_attribute "val", to: :val
      end

      def self.name
        "W14DocId"
      end
    end
  end

  # W15 DocId - model with its own namespace
  let(:w15_doc_id_class) do
    ns = w15_namespace
    Class.new do
      include Lutaml::Model::Serialize

      attribute :val, :string

      xml do
        element "docId"
        namespace ns
        map_attribute "val", to: :val
      end

      def self.name
        "W15DocId"
      end
    end
  end

  # W15 ChartTracking - model with its own namespace
  let(:w15_chart_tracking_class) do
    ns = w15_namespace
    Class.new do
      include Lutaml::Model::Serialize

      xml do
        element "chartTrackingRefBased"
        namespace ns
      end

      def self.name
        "W15ChartTracking"
      end
    end
  end

  # OOXML Settings model using delegation pattern for same-named elements
  let(:ooxml_settings_class) do
    w_ns = settings_namespace
    w14_ns = w14_namespace
    w15_ns = w15_namespace
    w14_class = w14_doc_id_class
    w15_class = w15_doc_id_class
    w15_ct_class = w15_chart_tracking_class

    Class.new do
      include Lutaml::Model::Serialize

      attribute :w14_doc_id, w14_class
      attribute :w15_doc_id, w15_class
      attribute :w15_chart_tracking, w15_ct_class
      attribute :write_protection, :boolean

      xml do
        root "settings"
        namespace w_ns
        namespace_scope [w14_ns, w15_ns]

        map_element "docId", to: :w14_doc_id
        map_element "chartTrackingRefBased", to: :w15_chart_tracking
        map_element "docId", to: :w15_doc_id
        map_element "writeProtection", to: :write_protection
      end

      def self.name
        "Settings"
      end
    end
  end

  # XML with same-named elements in different namespaces
  let(:ooxml_settings_xml) do
    <<~XML
      <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                  xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
                  xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml">
        <w14:docId w14:val="4C6D0839"/>
        <w15:chartTrackingRefBased/>
        <w15:docId w15:val="{A1B2C3D4-E5F6-7890}"/>
        <w:writeProtection w:enforce="0"/>
      </w:settings>
    XML
  end

  describe "Lutaml::Xml::Element" do
    describe "namespace attributes" do
      it "initializes with namespace_uri and namespace_prefix" do
        element = Lutaml::Xml::Element.new(
          "Element",
          "docId",
          node_type: :element,
          namespace_uri: "http://example.com/ns",
          namespace_prefix: "ex",
        )

        expect(element.namespace_uri).to eq("http://example.com/ns")
        expect(element.namespace_prefix).to eq("ex")
      end

      it "defaults namespace attributes to nil for backward compatibility" do
        element = Lutaml::Xml::Element.new("Element", "docId",
                                           node_type: :element)

        expect(element.namespace_uri).to be_nil
        expect(element.namespace_prefix).to be_nil
      end

      it "is still backward compatible with eql? and ==" do
        element1 = Lutaml::Xml::Element.new("Element", "docId",
                                            node_type: :element)
        element2 = Lutaml::Xml::Element.new(
          "Element", "docId", node_type: :element,
                              namespace_uri: "http://example.com/ns",
                              namespace_prefix: "ex"
        )

        expect(element1.eql?(element2)).to be true
        expect(element1 == element2).to be true
      end

      it "returns false for eql? with different type or name" do
        element1 = Lutaml::Xml::Element.new("Element", "docId",
                                            node_type: :element)
        element2 = Lutaml::Xml::Element.new("Element", "other",
                                            node_type: :element)

        expect(element1.eql?(element2)).to be false
      end

      it "registers namespace attributes for Liquid serialization" do
        element = Lutaml::Xml::Element.new(
          "Element",
          "docId",
          node_type: :element,
          namespace_uri: "http://example.com/ns",
          namespace_prefix: "ex",
        )

        liquid = element.to_liquid
        expect(liquid.namespace_uri).to eq("http://example.com/ns")
        expect(liquid.namespace_prefix).to eq("ex")
      end
    end
  end

  describe "XmlElement#order" do
    it "captures namespace_uri and namespace_prefix for child elements" do
      adapter = Lutaml::Xml.adapter
      xml = <<~XML
        <root xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
              xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml">
          <w14:docId>value1</w14:docId>
          <w15:docId>value2</w15:docId>
        </root>
      XML

      parsed = adapter.parse(xml)
      root = parsed.root

      # Get order and check namespace info
      order = root.order
      w14_element = order.find { |e| e.name == "docId" && e.namespace_uri == "http://schemas.microsoft.com/office/word/2010/wordml" }
      w15_element = order.find { |e| e.name == "docId" && e.namespace_uri == "http://schemas.microsoft.com/office/word/2012/wordml" }

      expect(w14_element).not_to be_nil
      expect(w14_element.namespace_uri).to eq("http://schemas.microsoft.com/office/word/2010/wordml")
      expect(w14_element.namespace_prefix).to eq("w14")

      expect(w15_element).not_to be_nil
      expect(w15_element.namespace_uri).to eq("http://schemas.microsoft.com/office/word/2012/wordml")
      expect(w15_element.namespace_prefix).to eq("w15")
    end

    it "captures default namespace as nil prefix" do
      adapter = Lutaml::Xml.adapter
      xml = <<~XML
        <root xmlns="http://example.com/default">
          <child>text</child>
        </root>
      XML

      parsed = adapter.parse(xml)
      root = parsed.root

      order = root.order
      child = order.find { |e| e.name == "child" }

      expect(child).not_to be_nil
      expect(child.namespace_uri).to eq("http://example.com/default")
      expect(child.namespace_prefix).to be_nil
    end

    it "marks elements without namespace with nil namespace_uri" do
      adapter = Lutaml::Xml.adapter
      xml = <<~XML
        <root>
          <child>text</child>
        </root>
      XML

      parsed = adapter.parse(xml)
      root = parsed.root

      order = root.order
      child = order.find { |e| e.name == "child" }

      expect(child).not_to be_nil
      expect(child.namespace_uri).to be_nil
    end
  end

  describe "Same-named element round-trip (integration test)" do
    # This is the key test - it verifies that serialization correctly handles
    # same-named elements from different namespaces. The fix stores namespace info
    # in element_order and uses it during rule matching.
    it "round-trips correctly with all namespaces preserved" do
      instance = ooxml_settings_class.from_xml(ooxml_settings_xml)
      serialized = instance.to_xml

      # Parse the serialized XML back
      reparsed = ooxml_settings_class.from_xml(serialized)

      expect(reparsed.w14_doc_id.val).to eq("4C6D0839")
      expect(reparsed.w15_doc_id.val).to eq("{A1B2C3D4-E5F6-7890}")
    end
  end

  describe "Round-trip serialization with same-named elements" do
    it "correctly parses same-named elements from different namespaces" do
      instance = ooxml_settings_class.from_xml(ooxml_settings_xml)

      expect(instance.w14_doc_id.val).to eq("4C6D0839")
      expect(instance.w15_doc_id.val).to eq("{A1B2C3D4-E5F6-7890}")
      expect(instance.w15_chart_tracking).to be_a(w15_chart_tracking_class)
      # write_protection: check value is parsed (format may vary)
      expect(instance.write_protection).not_to be_nil
    end

    it "round-trips correctly with all namespaces preserved" do
      instance = ooxml_settings_class.from_xml(ooxml_settings_xml)
      serialized = instance.to_xml

      # Parse the serialized XML back
      reparsed = ooxml_settings_class.from_xml(serialized)

      expect(reparsed.w14_doc_id.val).to eq("4C6D0839")
      expect(reparsed.w15_doc_id.val).to eq("{A1B2C3D4-E5F6-7890}")
    end

    it "serializes correct namespace prefixes for each element" do
      w14_val = w14_doc_id_class.new(val: "ABCD1234")
      w15_val = w15_doc_id_class.new(val: "EFGH5678")
      w15_ct = w15_chart_tracking_class.new

      instance = ooxml_settings_class.new(
        w14_doc_id: w14_val,
        w15_doc_id: w15_val,
        w15_chart_tracking: w15_ct,
        write_protection: true,
      )

      xml = instance.to_xml

      # w14:docId should have w14 prefix on the element
      expect(xml).to include("<w14:docId")

      # w15:docId should have w15 prefix on the element
      expect(xml).to include("<w15:docId")

      # chartTrackingRefBased should have w15 prefix
      expect(xml).to include("<w15:chartTrackingRefBased")

      # writeProtection should be present
      expect(xml).to include("writeProtection")
    end

    it "does not lose values when serializing multiple same-named elements" do
      w14_val = w14_doc_id_class.new(val: "W14-VALUE")
      w15_val = w15_doc_id_class.new(val: "W15-VALUE")
      w15_ct = w15_chart_tracking_class.new

      instance = ooxml_settings_class.new(
        w14_doc_id: w14_val,
        w15_doc_id: w15_val,
        w15_chart_tracking: w15_ct,
        write_protection: false,
      )

      # Serialize
      xml = instance.to_xml

      # Parse back
      reparsed = ooxml_settings_class.from_xml(xml)

      # Both values must be preserved (the original bug: w15_doc_id was lost)
      expect(reparsed.w14_doc_id.val).to eq("W14-VALUE")
      expect(reparsed.w15_doc_id.val).to eq("W15-VALUE")
    end
  end

  describe "Backward compatibility" do
    it "works with elements that have no namespace (nil namespace_uri)" do
      simple_ns = settings_namespace

      simple_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :title, :string
        attribute :author, :string

        xml do
          root "document"
          namespace simple_ns

          map_element "title", to: :title
          map_element "author", to: :author
        end

        def self.name
          "Document"
        end
      end

      xml = <<~XML
        <document xmlns="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <title>Test Title</title>
          <author>Test Author</author>
        </document>
      XML

      instance = simple_class.from_xml(xml)
      expect(instance.title).to eq("Test Title")
      expect(instance.author).to eq("Test Author")

      serialized = instance.to_xml
      reparsed = simple_class.from_xml(serialized)

      expect(reparsed.title).to eq("Test Title")
      expect(reparsed.author).to eq("Test Author")
    end

    it "element_order items from older code (without namespace) still work" do
      # Simulate an old Element object without namespace attributes
      old_element = Lutaml::Xml::Element.new("Element", "title",
                                             node_type: :element)

      expect(old_element.namespace_uri).to be_nil
      expect(old_element.namespace_prefix).to be_nil
      expect(old_element.name).to eq("title")
      expect(old_element.type).to eq("Element")
    end
  end

  describe "Element ordering with namespaces" do
    it "preserves original element order across namespaces" do
      instance = ooxml_settings_class.from_xml(ooxml_settings_xml)

      # Check that element_order is captured
      expect(instance).to respond_to(:element_order)

      # The order should contain all elements in sequence
      order = instance.element_order
      doc_ids = order.select { |e| e.name == "docId" }

      expect(doc_ids.size).to eq(2)
      # First docId should be w14
      expect(doc_ids[0].namespace_uri).to eq(
        "http://schemas.microsoft.com/office/word/2010/wordml",
      )
      # Second docId should be w15
      expect(doc_ids[1].namespace_uri).to eq(
        "http://schemas.microsoft.com/office/word/2012/wordml",
      )
    end
  end
end
