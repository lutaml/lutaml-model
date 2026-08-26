# frozen_string: true

require "spec_helper"
require_relative "../../../lib/lutaml/model"

# lutaml-model#758: a plain (unnamespaced) map_attribute rule on an
# element-namespaced class must not absorb a namespaced sibling attribute
# (and vice versa), and a type-level `namespace :blank` must not crash.
module ElementNsDisjointSpec
  class XmiNs < Lutaml::Xml::Namespace
    uri "http://www.example.com/xmi"
    prefix_default "xmi"
  end

  class ElemNs < Lutaml::Xml::Namespace
    uri "http://www.example.com/elem"
    prefix_default "e"
  end

  class XmiTypeAttr < Lutaml::Model::Type::String
    xml do
      namespace XmiNs
    end
  end

  class DocBase < Lutaml::Model::Serializable
    attribute :xmi_type, XmiTypeAttr

    xml do
      namespace ElemNs
      map_attribute "type", to: :xmi_type
    end
  end

  class Doc < DocBase
    attribute :plain_type, Lutaml::Model::Type::String

    xml do
      root "doc"
      map_attribute "type", to: :plain_type
    end
  end

  class BlankType < Lutaml::Model::Type::String
    xml do
      namespace :blank
    end
  end

  class BlankDoc < Lutaml::Model::Serializable
    attribute :v, BlankType
    xml do
      root "bd"
      map_attribute "v", to: :v
    end
  end
end

RSpec.describe "attribute namespace-disjointness on element-namespaced classes (#758)" do
  it "routes xmi:type to the namespaced slot and leaves plain_type nil" do
    doc = ElementNsDisjointSpec::Doc.from_xml(
      %(<doc xmlns:xmi="http://www.example.com/xmi" xmi:type="uml:Parameter"/>),
    )
    expect(doc.xmi_type).to eq("uml:Parameter")
    expect(doc.plain_type).to be_nil
  end

  it "routes an unprefixed type to plain_type, leaves xmi_type nil" do
    doc = ElementNsDisjointSpec::Doc.from_xml(%(<doc type="EAnone_void"/>))
    expect(doc.plain_type).to eq("EAnone_void")
    expect(doc.xmi_type).to be_nil
  end

  it "round-trips both spellings without emitting a spurious duplicate" do
    doc = ElementNsDisjointSpec::Doc.from_xml(
      %(<doc xmlns:xmi="http://www.example.com/xmi" xmi:type="uml:Parameter"/>),
    )
    out = doc.to_xml.strip
    expect(out).to include('xmi:type="uml:Parameter"')
    expect(out).not_to match(/\stype="uml:Parameter"/)
  end

  it "survives type-level namespace :blank without crashing" do
    expect do
      ElementNsDisjointSpec::BlankDoc.from_xml(%(<bd v="x"/>))
    end.not_to raise_error
  end
end
