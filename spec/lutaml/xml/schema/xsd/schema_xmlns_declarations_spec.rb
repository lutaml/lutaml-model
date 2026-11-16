# frozen_string_literal: true

# lutaml-model#1131: parsed schemas retain the document's xmlns
# declarations so qualified QNames resolve exactly. particlesQ032's
# chameleon-import class imports three documents each declaring a
# global `e2`; the content model references foo:e2 / x:e2 / bar:e2 —
# the prefixes ARE the semantics, and the declaration plan's
# URI-keyed registry cannot represent several prefixes bound to one
# URI.

require "lutaml/model"
require "lutaml/xml/schema/xsd"

RSpec.describe "xmlns declarations retained on parsed Schema" do
  let(:xsd) do
    <<~XML
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns:foo="http://example.com/foo"
                 xmlns:x="http://example.com/foo"
                 xmlns:bar="http://example.com/bar"
                 targetNamespace="http://example.com/main"
                 elementFormDefault="qualified">
        <xs:import namespace="http://example.com/foo"/>
        <xs:import namespace="http://example.com/bar"/>
        <xs:element name="root">
          <xs:complexType>
            <xs:sequence>
              <xs:element ref="foo:e2"/>
              <xs:element ref="x:e2"/>
              <xs:element ref="bar:e2"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XML
  end

  let(:schema) do
    Lutaml::Xml::Schema::Xsd.parse(xsd, location: "particles_q032.xsd")
  end

  it "retains every declared prefix with its URI" do
    declarations = schema.xmlns_declarations
    expect(declarations["xs"]).to eq("http://www.w3.org/2001/XMLSchema")
    expect(declarations["foo"]).to eq("http://example.com/foo")
    expect(declarations["x"]).to eq("http://example.com/foo")
    expect(declarations["bar"]).to eq("http://example.com/bar")
  end

  it "keeps prefixes the declaration plan's URI-keyed registry collapses" do
    # foo: and x: bind the SAME URI — an exact prefix→URI map must
    # carry both spellings; the plan registry keeps only the last.
    expect(schema.xmlns_declarations.fetch("foo"))
      .to eq(schema.xmlns_declarations.fetch("x"))
  end

  it "resolves the particlesQ032 reference prefixes exactly" do
    declarations = schema.xmlns_declarations
    %w[foo x bar].each do |prefix|
      expect(declarations).to have_key(prefix)
      expect(declarations[prefix]).to start_with("http://example.com/")
    end
  end

  it "captures a plain XML document's declarations with the default under nil" do
    ns = Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/doc"
      prefix_default "d"
    end
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :child, :string

      xml do
        namespace ns
        element "doc"
        map_element "child", to: :child
      end
    end

    instance = model.from_xml(
      '<doc xmlns="http://example.com/doc" ' \
      'xmlns:p="http://example.com/p"><child>x</child></doc>',
    )
    expect(instance.xmlns_declarations[nil]).to eq("http://example.com/doc")
    expect(instance.xmlns_declarations["p"]).to eq("http://example.com/p")
  end
end
