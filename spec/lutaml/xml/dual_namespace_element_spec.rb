# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

RSpec.describe "Dual-namespace same-named elements" do
  let(:math_ns_class) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/officeDocument/2006/math"
      prefix_default "m"
      element_form_default :qualified
    end
  end

  let(:wml_ns_class) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      prefix_default "w"
      element_form_default :qualified
    end
  end

  let(:parent_class) do
    m_ns = math_ns_class
    w_ns = wml_ns_class

    child_math = Class.new(Lutaml::Model::Serializable) do
      attribute :script, :string
      xml do
        element "rPr"
        namespace m_ns
        map_attribute "val", to: :script
      end
    end

    child_word = Class.new(Lutaml::Model::Serializable) do
      attribute :fonts, :string
      xml do
        element "rPr"
        namespace w_ns
        map_attribute "ascii", to: :fonts
      end
    end

    Class.new(Lutaml::Model::Serializable) do
      attribute :math_props, child_math
      attribute :word_props, child_word
      attribute :text, :string

      xml do
        element "r"
        namespace m_ns

        map_element "rPr", to: :math_props, render_nil: false
        map_element "rPr", to: :word_props, render_nil: false
        map_element "t", to: :text, render_nil: false
      end
    end
  end

  let(:xml) do
    math_uri = math_ns_class.uri
    wml_uri = wml_ns_class.uri
    <<~XML
      <m:r xmlns:m="#{math_uri}" xmlns:w="#{wml_uri}">
        <m:rPr m:val="roman"/>
        <w:rPr w:ascii="Times New Roman"/>
        <m:t>hello</m:t>
      </m:r>
    XML
  end

  def namespace_prefix(obj)
    obj.instance_variable_get(:@__xml_namespace_prefix)
  end

  it "deserializes math_properties with m: prefix" do
    result = parent_class.from_xml(xml)
    expect(result.math_props).not_to be_nil
    expect(namespace_prefix(result.math_props)).to eq("m")
  end

  it "deserializes word_properties with w: prefix" do
    result = parent_class.from_xml(xml)
    expect(result.word_props).not_to be_nil
    expect(namespace_prefix(result.word_props)).to eq("w")
  end

  it "deserializes word_properties child elements correctly" do
    result = parent_class.from_xml(xml)
    expect(result.word_props.fonts).to eq("Times New Roman")
  end

  it "does not leak namespace prefix between siblings" do
    result = parent_class.from_xml(xml)
    expect(namespace_prefix(result.math_props)).to eq("m")
    expect(namespace_prefix(result.word_props)).to eq("w")
  end

  it "round-trips with correct namespace prefixes" do
    result = parent_class.from_xml(xml)
    output = result.to_xml
    expect(output).to include("<m:rPr")
    expect(output).to include("<w:rPr")
  end

  it "round-trip preserves data integrity through parse-serialize-parse cycle" do
    result = parent_class.from_xml(xml)
    serialized = result.to_xml
    reparsed = parent_class.from_xml(serialized)

    expect(reparsed.math_props.script).to eq("roman")
    expect(reparsed.word_props.fonts).to eq("Times New Roman")
    expect(reparsed.text).to eq("hello")
  end

  it "handles nested elements within dual-namespace children" do
    m_ns = math_ns_class
    w_ns = wml_ns_class

    child_word_with_nested = Class.new(Lutaml::Model::Serializable) do
      attribute :fonts, :string
      attribute :bold, :string
      xml do
        element "rPr"
        namespace w_ns
        map_attribute "ascii", to: :fonts
        map_attribute "b", to: :bold
      end
    end

    parent_with_nested = Class.new(Lutaml::Model::Serializable) do
      attribute :word_props, child_word_with_nested
      xml do
        element "r"
        namespace m_ns
        map_element "rPr", to: :word_props, render_nil: false
      end
    end

    complex_xml = <<~XML
      <m:r xmlns:m="#{math_ns_class.uri}" xmlns:w="#{wml_ns_class.uri}">
        <w:rPr w:ascii="Courier New" w:b="1"/>
      </m:r>
    XML

    result = parent_with_nested.from_xml(complex_xml)
    expect(result.word_props.fonts).to eq("Courier New")
    expect(result.word_props.bold).to eq("1")

    serialized = result.to_xml
    expect(serialized).to include("<w:rPr")

    reparsed = parent_with_nested.from_xml(serialized)
    expect(reparsed.word_props.fonts).to eq("Courier New")
    expect(reparsed.word_props.bold).to eq("1")
  end

  it "handles nil values gracefully in dual-namespace context" do
    instance = parent_class.new(
      math_props: nil,
      word_props: nil,
      text: "test",
    )

    output = instance.to_xml
    expect(output).to include("<t>test</t>")
    expect(output).to include("xmlns=\"#{math_ns_class.uri}\"")
  end

  it "does not confuse prefixes between math and word namespaces" do
    result = parent_class.from_xml(xml)

    expect(result.math_props.instance_variable_get(:@__xml_namespace_prefix)).to eq("m")
    expect(result.word_props.instance_variable_get(:@__xml_namespace_prefix)).to eq("w")

    serialized = result.to_xml
    expect(serialized.scan("<m:rPr").count).to eq(1)
    expect(serialized.scan("<w:rPr").count).to eq(1)
  end
end
