# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "XSD 1.1 constructs (#1203)" do
  it "maps xs:assert on a complexType from the parsed XSD" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:sequence>
            <xs:element name="a" maxOccurs="unbounded"/>
          </xs:sequence>
          <xs:assert test="count(xs:a) &gt; 1"
                     xpathDefaultNamespace="##targetNamespace"/>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    assert = schema.complex_type.first.assert.first

    expect(assert).not_to be_nil
    expect(assert.test).to eq("count(xs:a) > 1")
    expect(assert.xpath_default_namespace).to eq("##targetNamespace")
  end

  it "maps xs:assert inside simpleContent and complexContent " \
     "derivations" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="simple">
          <xs:simpleContent>
            <xs:extension base="xs:string">
              <xs:assert test="string-length(.) &gt; 0"/>
            </xs:extension>
          </xs:simpleContent>
        </xs:complexType>
        <xs:complexType name="complex">
          <xs:complexContent>
            <xs:restriction base="xs:anyType">
              <xs:assert test="true()"/>
            </xs:restriction>
          </xs:complexContent>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    simple = schema.complex_type.find { |t| t.name == "simple" }
    complex = schema.complex_type.find { |t| t.name == "complex" }

    expect(simple.simple_content.extension.assert.first.test)
      .to eq("string-length(.) > 0")
    expect(complex.complex_content.restriction.assert.first.test)
      .to eq("true()")
  end

  it "maps xs:openContent on a complexType" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:sequence>
            <xs:element name="a"/>
          </xs:sequence>
          <xs:openContent mode="suffix"/>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    open_content = schema.complex_type.first.open_content

    expect(open_content).not_to be_nil
    expect(open_content.mode).to eq("suffix")
  end

  it "maps xs:alternative on an element declaration" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="shape">
          <xs:alternative test="@kind='circle'" type="CircleType"
                          xpathDefaultNamespace="##targetNamespace"/>
          <xs:alternative type="DefaultType"/>
        </xs:element>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    alternatives = schema.element.first.alternative

    expect(alternatives.map(&:type)).to eq(%w[CircleType DefaultType])
    expect(alternatives.first.test).to eq("@kind='circle'")
    expect(alternatives.first.xpath_default_namespace)
      .to eq("##targetNamespace")
  end

  it "round-trips the constructs through to_xml" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:openContent mode="interleave"/>
          <xs:assert test="true()"/>
        </xs:complexType>
        <xs:element name="e">
          <xs:alternative test="@k='v'" type="T"/>
        </xs:element>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    emitted = schema.to_xml

    expect(emitted).to include("<xs:assert")
    expect(emitted).to include('test="true()"')
    expect(emitted).to include("<xs:openContent")
    expect(emitted).to include('mode="interleave"')
    expect(emitted).to include("<xs:alternative")
    expect(emitted).to include('type="T"')
  end

  it "maps xs:assertion on a simpleType restriction" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:simpleType name="num">
          <xs:restriction base="xs:string">
            <xs:assertion test="$value castable as xs:double"/>
          </xs:restriction>
        </xs:simpleType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    assertion = schema.simple_type.first.restriction.assertion.first

    expect(assertion).not_to be_nil
    expect(assertion.test).to eq("$value castable as xs:double")
  end

  it "keeps the xs:any wildcard on xs:openContent" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:sequence>
            <xs:element name="a"/>
          </xs:sequence>
          <xs:openContent mode="interleave">
            <xs:any namespace="http://open.example/" processContents="lax"/>
          </xs:openContent>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    any = schema.complex_type.first.open_content.any

    expect(any).not_to be_nil
    expect(any.namespace).to eq("http://open.example/")
    expect(any.process_contents).to eq("lax")
  end

  it "keeps the wildcard negation attributes on xs:any and xs:anyAttribute (#1221)" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:sequence>
            <xs:any notQName="xs:foo ##local" processContents="lax"/>
          </xs:sequence>
          <xs:anyAttribute notNamespace="http://apple.com/ http://devil.com/"
                           processContents="skip"/>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)
    complex_type = schema.complex_type.first

    aggregate_failures do
      expect(complex_type.sequence.any.first.not_qname).to eq("xs:foo ##local")
      expect(complex_type.any_attribute.not_namespace)
        .to eq("http://apple.com/ http://devil.com/")
    end
  end

  it "round-trips the wildcard negation attributes through to_xml (#1221)" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="t">
          <xs:sequence>
            <xs:any notQName="##targetNamespace" processContents="lax"/>
          </xs:sequence>
          <xs:anyAttribute notNamespace="##local" processContents="skip"/>
        </xs:complexType>
      </xs:schema>
    XSD

    out = Lutaml::Xml::Schema::Xsd.parse(xsd).to_xml

    aggregate_failures do
      expect(out).to include('notQName="##targetNamespace"')
      expect(out).to include('notNamespace="##local"')
    end
  end

  it "parses the vc versioning attributes and round-trips them qualified (#1222)" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns:vc="http://www.w3.org/2007/XMLSchema-versioning"
                 vc:minVersion="1.1">
        <xs:complexType name="t">
          <xs:sequence>
            <xs:element name="a"/>
          </xs:sequence>
        </xs:complexType>
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)

    expect(schema.vc_min_version).to eq("1.1")

    out = schema.to_xml

    aggregate_failures do
      expect(out).to include('vc:minVersion="1.1"')
      expect(out).to include('xmlns:vc="http://www.w3.org/2007/XMLSchema-versioning"')
    end
  end

  it "keeps vc:maxVersion beside vc:minVersion (#1222)" do
    xsd = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns:vc="http://www.w3.org/2007/XMLSchema-versioning"
                 vc:minVersion="1.0" vc:maxVersion="1.1">
      </xs:schema>
    XSD

    schema = Lutaml::Xml::Schema::Xsd.parse(xsd)

    aggregate_failures do
      expect(schema.vc_min_version).to eq("1.0")
      expect(schema.vc_max_version).to eq("1.1")
      expect(schema.to_xml).to include('vc:maxVersion="1.1"')
    end
  end
end
