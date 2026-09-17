# frozen_string_literal: true

require "spec_helper"

# An attribute rule with no namespace of its own whose VALUE TYPE is
# namespace-qualified (Lutaml::Xml::Type::Configurable) must keep
# binding unprefixed source attributes — per W3C Namespaces an
# unprefixed attribute carries no namespace, and 0.8.19 matched it
# leniently. The #758 strict prefixed-only match applies to rule- and
# schema-level qualification, not to the value type's (lutaml-model#786).
module TypeQualifiedAttributeLeniencySpec
  class W14Ns < Lutaml::Xml::Namespace
    uri "http://schemas.microsoft.com/office/word/2010/wordml"
    prefix_default "w14"
    element_form_default :qualified
    attribute_form_default :qualified
  end

  class W14String < Lutaml::Model::Type::String
    include Lutaml::Xml::Type::Configurable

    xml do
      namespace W14Ns
    end
  end

  class WNs < Lutaml::Xml::Namespace
    uri "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    prefix_default "w"
    element_form_default :qualified
  end

  W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  W14_NS = "http://schemas.microsoft.com/office/word/2010/wordml"

  class Bookmark < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :v, W14String

    xml do
      element "bookmarkStart"
      namespace WNs
      map_attribute "id", to: :id
      map_attribute "displacedByCustomXml", to: :v
    end
  end
end

RSpec.describe "type-qualified attribute rules" do
  it "bind unprefixed source attributes (W3C: unprefixed = no namespace)" do
    xml = %(<w:bookmarkStart xmlns:w="#{TypeQualifiedAttributeLeniencySpec::W_NS}" displacedByCustomXml="next" id="0"/>)
    doc = TypeQualifiedAttributeLeniencySpec::Bookmark.from_xml(xml)

    expect(doc.v).to eq("next")
    expect(doc.id).to eq("0")
    expect(doc.to_xml).to include(%(w14:displacedByCustomXml="next"))
  end

  it "keep binding prefixed source attributes in the type namespace" do
    xml = %(<w:bookmarkStart xmlns:w="#{TypeQualifiedAttributeLeniencySpec::W_NS}" xmlns:w14="#{TypeQualifiedAttributeLeniencySpec::W14_NS}" w14:displacedByCustomXml="next" id="0"/>)
    doc = TypeQualifiedAttributeLeniencySpec::Bookmark.from_xml(xml)

    expect(doc.v).to eq("next")
    expect(doc.to_xml).to include(%(w14:displacedByCustomXml="next"))
  end
end
