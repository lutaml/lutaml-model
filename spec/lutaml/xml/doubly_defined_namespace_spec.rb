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

    it "round-trips doubly-defined: default ns + prefixed child on root" do
      xml = <<~XML
        <root xmlns="http://example.com/items" xmlns:b="http://example.com/items">
          <b:item>hello</b:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      expect(model.item).to eq("hello")

      output = model.to_xml
      expect(output).to include('xmlns="http://example.com/items"')
      expect(output).to include('xmlns:b="http://example.com/items"')
      expect(output).to include("<b:item>hello</b:item>")
    end

    it "round-trips doubly-defined: only prefixed ns on root" do
      xml = <<~XML
        <root xmlns:c="http://example.com/items">
          <c:item>hello</c:item>
        </root>
      XML

      model = model_class.from_xml(xml)
      expect(model.item).to eq("hello")

      output = model.to_xml
      expect(output).to include('xmlns:c="http://example.com/items"')
      expect(output).to include("<c:item>hello</c:item>")
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
      plan = model.import_declaration_plan

      expect(plan).to be_a(Lutaml::Xml::DeclarationPlan)
      expect(plan.input_prefix_formats).to include("xyzabc:http://example.com/items" => :prefix)
    end

    it "input_prefix_formats includes default namespace format" do
      xml = '<root xmlns="http://example.com/items"><item>x</item></root>'

      model = model_class.from_xml(xml)
      plan = model.import_declaration_plan

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
      expect(output).to include("<xyzabc:Inner>")
      expect(output).to include("<xyzabc:name>from xyzabc</xyzabc:name>")
    end

    it "round-trips doubly-defined: default ns on outer, prefixed child" do
      xml = <<~XML
        <Outer xmlns="http://example.com/items" xmlns:d="http://example.com/items">
          <d:Inner><d:name>from d</d:name></d:Inner>
        </Outer>
      XML

      model = outer_class.from_xml(xml)
      expect(model.child.name).to eq("from d")

      output = model.to_xml
      expect(output).to include('xmlns:d="http://example.com/items"')
      expect(output).to include("<d:Inner>")
      expect(output).to include("<d:name>from d</d:name>")
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

  describe "child element with foreign namespace preserves prefix format" do
    # Regression test: child element in a different namespace from parent
    # must preserve its prefix format during round-trip. Using default format
    # (xmlns="child-uri") would override the parent's default namespace scope,
    # losing namespace context for descendants.
    let(:parent_ns) do
      Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/parent"
        prefix_default "p"
        element_form_default :qualified
      end
    end

    let(:child_ns) do
      Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://example.com/child"
        prefix_default "c"
        element_form_default :qualified
      end
    end

    let(:child_model) do
      ns = child_ns
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          root "child"
          namespace ns
          map_content to: :value
        end
      end
    end

    let(:parent_model) do
      ns = parent_ns
      cm = child_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :child, cm

        xml do
          root "parent"
          namespace ns
          map_element "name", to: :name
          map_element "child", to: :child
        end
      end
    end

    it "preserves child element prefix when child namespace differs from parent" do
      xml = <<~XML
        <parent xmlns="http://example.com/parent">
          <name>test</name>
          <c:child xmlns:c="http://example.com/child">child value</c:child>
        </parent>
      XML

      model = parent_model.from_xml(xml)
      expect(model.name).to eq("test")
      expect(model.child.value).to eq("child value")

      output = model.to_xml

      # Child element must use PREFIX format to preserve parent's default namespace
      expect(output).to include('xmlns:c="http://example.com/child"')
      expect(output).to include("<c:child")
      # Parent's default namespace must NOT be overridden by child
      expect(output).to include('xmlns="http://example.com/parent"')
    end

    it "does not hoist child namespace to root when declared only on child element" do
      xml = <<~XML
        <parent xmlns="http://example.com/parent">
          <name>test</name>
          <c:child xmlns:c="http://example.com/child">child value</c:child>
        </parent>
      XML

      model = parent_model.from_xml(xml)

      expected = <<~XML.strip
        <parent xmlns="http://example.com/parent">
          <name>test</name>
          <c:child xmlns:c="http://example.com/child">child value</c:child>
        </parent>
      XML

      expect(model.to_xml).to be_xml_equivalent_to(expected)
    end
  end

  describe "import_declaration_plan option" do
    let(:prefixed_xml) do
      <<~XML
        <root xmlns:xyzabc="http://example.com/items">
          <xyzabc:item>x</xyzabc:item>
        </root>
      XML
    end

    describe ":lazy (default)" do
      it "stores collected namespace data during parsing" do
        model = model_class.from_xml(prefixed_xml)
        expect(model.pending_namespace_data).not_to be_nil
      end

      it "builds plan via import_declaration_plan method" do
        model = model_class.from_xml(prefixed_xml)
        expect(model.import_declaration_plan).to be_a(Lutaml::Xml::DeclarationPlan)
      end

      it "clears namespace data after plan is built" do
        model = model_class.from_xml(prefixed_xml)
        expect(model.pending_namespace_data).not_to be_nil
        _ = model.import_declaration_plan
        expect(model.pending_namespace_data).to be_nil
      end

      it "imports plan automatically on to_xml" do
        model = model_class.from_xml(prefixed_xml)
        # Plan not yet built (instance variable is nil)
        expect(model.instance_variable_get(:@xml_declaration_plan)).to be_nil
        model.to_xml
        # After to_xml, plan is built and cached
        expect(model.import_declaration_plan).to be_a(Lutaml::Xml::DeclarationPlan)
      end
    end

    describe ":eager" do
      it "builds plan immediately during parsing" do
        model = model_class.from_xml(prefixed_xml,
                                     import_declaration_plan: :eager)
        expect(model.pending_namespace_data).to be_nil
        expect(model.import_declaration_plan).to be_a(Lutaml::Xml::DeclarationPlan)
      end
    end

    describe ":skip" do
      it "never builds plan" do
        model = model_class.from_xml(prefixed_xml,
                                     import_declaration_plan: :skip)
        expect(model.pending_namespace_data).to be_nil
        expect(model.import_declaration_plan).to be_nil
      end
    end

    describe "invalid values" do
      it "raises error for boolean true" do
        expect do
          model_class.from_xml(prefixed_xml, import_declaration_plan: true)
        end
          .to raise_error(/must be :eager, :lazy, or :skip/)
      end

      it "raises error for boolean false" do
        expect do
          model_class.from_xml(prefixed_xml, import_declaration_plan: false)
        end
          .to raise_error(/must be :eager, :lazy, or :skip/)
      end

      it "raises error for unknown symbol" do
        expect do
          model_class.from_xml(prefixed_xml, import_declaration_plan: :bogus)
        end
          .to raise_error(/must be :eager, :lazy, or :skip/)
      end
    end
  end
end
