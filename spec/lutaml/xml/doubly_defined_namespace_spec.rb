# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Doubly-defined namespace prefixes" do
  before do
    Lutaml::Model::GlobalContext.clear_caches
    Lutaml::Model::TransformationRegistry.instance.clear
    Lutaml::Model::GlobalRegister.instance.reset
  end

  let(:ns_class) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/items"
      prefix_default "a"
    end
  end

  let(:model_class) do
    ns = ns_class
    Class.new(Lutaml::Model::Serializable) do
      attribute :item, :string

      xml do
        root "root"
        namespace ns
        map_element "item", to: :item
      end
    end
  end

  describe "round-trip with unknown/arbitrary prefix" do
    it "round-trips with completely arbitrary prefix name" do
      xml = <<~XML
        <root xmlns:xyzabc="http://example.com/items">
          <xyzabc:item>hello</xyzabc:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      expect(model.item).to eq("hello")

      output = model.to_xml
      expect(output).to include('xmlns:xyzabc="http://example.com/items"')
      expect(output).to include("<xyzabc:item>hello</xyzabc:item>")
    end

    it "round-trips with default prefix (no prefix in element name)" do
      xml = <<~XML
        <root xmlns="http://example.com/items">
          <item>hello</item>
        </root>
      XML

      model = model_class.from_xml(xml)
      expect(model.item).to eq("hello")

      output = model.to_xml
      expect(output).to include('xmlns="http://example.com/items"')
      # Item has no namespace declaration, so it opts out of parent's default namespace
      expect(output).to include("<item xmlns=\"\">hello</item>")
    end

    it "round-trips with model-default prefix (a:)" do
      xml = <<~XML
        <root xmlns:a="http://example.com/items">
          <a:item>hello</a:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      expect(model.item).to eq("hello")

      output = model.to_xml
      expect(output).to include('xmlns:a="http://example.com/items"')
      expect(output).to include("<a:item>hello</a:item>")
    end
  end

  describe "cross-parse: explicit format override" do
    it "can parse prefixed and serialize with default format" do
      xml = <<~XML
        <root xmlns:a="http://example.com/items">
          <a:item>test</a:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      output = model.to_xml(prefix: false)

      expect(output).to include('xmlns="http://example.com/items"')
      expect(output).not_to include("xmlns:a=")
    end

    it "can parse with default and serialize with prefixed" do
      xml = <<~XML
        <root xmlns="http://example.com/items">
          <item>test</item>
        </root>
      XML

      model = model_class.from_xml(xml)
      output = model.to_xml(prefix: true)

      expect(output).to include('xmlns:a="http://example.com/items"')
      expect(output).not_to include('xmlns="http://example.com/items"')
    end
  end

  describe "input_prefix_formats tracking" do
    it "DeclarationPlan captures per-prefix-URI format" do
      xml = <<~XML
        <root xmlns:xyzabc="http://example.com/items">
          <xyzabc:item>x</xyzabc:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      plan = model.xml_declaration_plan

      expect(plan).to be_a(Lutaml::Xml::DeclarationPlan)
      expect(plan.input_prefix_formats).to include("xyzabc:http://example.com/items" => :prefix)
    end

    it "input_prefix_formats includes default namespace format" do
      xml = '<root xmlns="http://example.com/items"><item>x</item></root>'

      model = model_class.from_xml(xml)
      plan = model.xml_declaration_plan

      expect(plan).to be_a(Lutaml::Xml::DeclarationPlan)
      expect(plan.input_prefix_formats).to include(":http://example.com/items" => :default)
    end
  end

  describe "nested models with doubly-defined prefixes" do
    let(:inner_class) do
      ns = ns_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          root "Inner"
          namespace ns
          map_element "name", to: :name
        end
      end
    end

    let(:outer_class) do
      ns = ns_class
      ic = inner_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :child, ic

        xml do
          root "Outer"
          namespace ns
          map_element "Inner", to: :child
        end
      end
    end

    it "preserves prefix variant for nested model element" do
      xml = <<~XML
        <Outer xmlns:xyzabc="http://example.com/items">
          <xyzabc:Inner><xyzabc:name>from xyzabc</xyzabc:name></xyzabc:Inner>
        </Outer>
      XML

      model = outer_class.from_xml(xml)
      expect(model.child.name).to eq("from xyzabc")

      output = model.to_xml
      expect(output).to include('xmlns:xyzabc="http://example.com/items"')
      # Note: Inner has attributes, so no ">" immediately after the tag name
      expect(output).to include("<xyzabc:Inner ")
      expect(output).to include("<xyzabc:name>from xyzabc</xyzabc:name>")
    end
  end

  describe "format chooser uses input_prefix_formats" do
    it "uses prefix format from input_prefix_formats" do
      xml = <<~XML
        <root xmlns:xyzabc="http://example.com/items">
          <xyzabc:item>value</xyzabc:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      output = model.to_xml

      # Should preserve prefix format (from input_prefix_formats)
      expect(output).to include('xmlns:xyzabc="http://example.com/items"')
      expect(output).to include("<xyzabc:item>value</xyzabc:item>")
    end
  end
end
