# frozen_string_literal: true

require "spec_helper"

# Two map_attribute rules that share a local name but are distinguished by
# their type classes' bound namespaces must parse disjointly, mirroring
# serialization (lutaml-model#744).
#
# The coexisting-spelling cases under nokogiri/rexml additionally require the
# moxml adapter fixes (lutaml/moxml#94, lutaml/moxml#95); oga and ox already
# preserve same-local-name attributes across namespaces.
module AttributeNamespaceDisjointnessSpec
  class XmiNs < Lutaml::Xml::Namespace
    uri "http://www.example.com/xmi"
    prefix_default "xmi"
  end

  class XmiNsType < Lutaml::Model::Type::String
    xml do
      namespace XmiNs
    end
  end

  class Probe < Lutaml::Model::Serializable
    attribute :xmi_type, XmiNsType
    attribute :plain_type, Lutaml::Model::Type::String

    xml do
      element "probe"
      map_attribute "type", to: :xmi_type
      map_attribute "type", to: :plain_type
    end
  end

  def self.parse(xml, adapter)
    Lutaml::Model::Config.with_adapter(xml: adapter) { Probe.from_xml(xml) }
  end
end

RSpec.describe "Attribute namespace-disjoint parsing" do
  let(:namespaced_xmi) do
    %(<probe xmlns:xmi="http://www.example.com/xmi" xmi:type="uml:Parameter"/>)
  end

  let(:namespaced_foo) do
    %(<probe xmlns:foo="http://www.example.com/xmi" foo:type="uml:Parameter"/>)
  end

  let(:plain) { %(<probe type="EAnone_void"/>) }

  let(:both_spellings) do
    %(<probe xmlns:xmi="http://www.example.com/xmi" xmi:type="uml:Parameter" type="EAnone_void"/>)
  end

  let(:both_spellings_plain_first) do
    %(<probe type="EAnone_void" xmlns:xmi="http://www.example.com/xmi" xmi:type="uml:Parameter"/>)
  end

  %i[oga ox nokogiri].each do |adapter|
    context "with the #{adapter} adapter" do
      it "routes a namespaced rule to the attribute bound to its URI" do
        probe = AttributeNamespaceDisjointnessSpec.parse(namespaced_xmi, adapter)

        expect(probe.xmi_type).to eq("uml:Parameter")
        expect(probe.plain_type).to be_nil
      end

      it "accepts any prefix bound to the namespace URI" do
        probe = AttributeNamespaceDisjointnessSpec.parse(namespaced_foo, adapter)

        expect(probe.xmi_type).to eq("uml:Parameter")
        expect(probe.plain_type).to be_nil
      end

      it "does not let a namespace-less attribute satisfy the namespaced rule" do
        probe = AttributeNamespaceDisjointnessSpec.parse(plain, adapter)

        expect(probe.xmi_type).to be_nil
        expect(probe.plain_type).to eq("EAnone_void")
      end
    end
  end

  # Same-local-name attributes coexisting on one element require the moxml
  # fixes (lutaml/moxml#94 drops one under nokogiri; lutaml/moxml#95 crashes
  # under rexml), so these cases run on the adapters that preserve both.
  %i[oga ox].each do |adapter|
    context "with the #{adapter} adapter" do
      it "keeps both spellings disjoint regardless of document order" do
        [both_spellings, both_spellings_plain_first].each do |xml|
          probe = AttributeNamespaceDisjointnessSpec.parse(xml, adapter)

          expect(probe.xmi_type).to eq("uml:Parameter")
          expect(probe.plain_type).to eq("EAnone_void")
        end
      end
    end
  end

  describe "serialization" do
    it "writes each rule in its own namespace" do
      probe = AttributeNamespaceDisjointnessSpec::Probe.new(
        xmi_type: "uml:Parameter",
        plain_type: "EAnone_void",
      )

      expect(probe.to_xml.strip).to be_xml_equivalent_to(
        %(<probe xmlns:xmi="http://www.example.com/xmi" xmi:type="uml:Parameter" type="EAnone_void"/>),
      )
    end

    it "round-trips both spellings through parsing" do
      probe = AttributeNamespaceDisjointnessSpec::Probe.new(
        xmi_type: "uml:Parameter",
        plain_type: "EAnone_void",
      )
      reparsed = AttributeNamespaceDisjointnessSpec.parse(probe.to_xml, :oga)

      expect(reparsed.xmi_type).to eq("uml:Parameter")
      expect(reparsed.plain_type).to eq("EAnone_void")
    end
  end
end
