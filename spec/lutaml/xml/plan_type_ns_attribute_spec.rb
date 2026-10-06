# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML plan fast path: type-namespaced attribute rows" do
  # Attribute identity is (URI, local) (lutaml-model#744). A map_attribute
  # whose TYPE carries a namespace class used to opt the whole model out
  # of the plan path; it now compiles into an exact-URI AttrPlan ns row
  # (libleptris 1.9.289) with the sole-claimant lenient recovery keeping
  # the interpretive exact-first-then-any-qualification precedence.

  let(:wml_ns) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/type-ns/wml"
      prefix_default "w"
    end
  end

  let(:val_type) do
    stub_const("PlanTypeNsAttr::WmlNs", wml_ns)
    type = Class.new(Lutaml::Model::Type::String) do
      include Lutaml::Xml::Type::Configurable

      xml do
        namespace PlanTypeNsAttr::WmlNs
      end
    end
    stub_const("PlanTypeNsAttr::ValType", type)
    type
  end

  let(:klass) do
    val_type
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :val, PlanTypeNsAttr::ValType

      xml do
        element "keepNext"
        namespace PlanTypeNsAttr::WmlNs
        map_attribute "val", to: :val
      end
    end
    stub_const("PlanTypeNsAttr::KeepNext", model)
    model
  end

  around do |example|
    old = Lutaml::Model::Config.instance.xml_plan_fast_path
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = old
  end

  it "compiles a model whose attribute type carries a namespace" do
    plan = Lutaml::Xml::Leptris::PlanCompiler.compile(
      klass, Lutaml::Model::Config.default_register
    )

    expect(plan).not_to be_nil
    ns_row = plan[:tree][:attributes].find { |a| a[:name] == "val" }
    expect(ns_row[:ns]).to eq(exact: "http://example.com/type-ns/wml")
  end

  it "binds the attribute from the type's namespace" do
    doc = %(<w:keepNext xmlns:w="http://example.com/type-ns/wml" w:val="yes"/>)

    expect(klass.from_xml(doc).val).to eq("yes")
  end

  # The interpretive matcher refuses an ambiguous local name outright:
  # a foreign spelling alongside the canonical one binds nothing. The
  # exact-URI row mirrors that refusal (lutaml-model#744).
  it "refuses to bind when a foreign spelling accompanies the canonical one" do
    doc = '<w:keepNext xmlns:w="http://example.com/type-ns/wml" ' \
          'xmlns:f="http://example.com/foreign" val="foreign" w:val="canonical"/>'

    expect(klass.from_xml(doc).val).to be_nil
  end

  # Interpretive parity: the plan path resolves exactly as the
  # interpretive matcher (nokogiri) does on every spelling shape.
  it "matches the interpretive path's resolution on all spelling shapes" do
    canonical = %(<w:keepNext xmlns:w="http://example.com/type-ns/wml" w:val="yes"/>)
    ambiguous = '<w:keepNext xmlns:w="http://example.com/type-ns/wml" ' \
                'xmlns:f="http://example.com/foreign" val="foreign" w:val="canonical"/>'
    foreign_only = '<w:keepNext xmlns:f="http://example.com/foreign" ' \
                   'xmlns:w="http://example.com/type-ns/wml" val="foreign"/>'

    [canonical, ambiguous, foreign_only].each do |doc|
      interpretive = Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
        klass.from_xml(doc).val
      end

      expect(klass.from_xml(doc).val).to eq(interpretive)
    end
  end

  # A type declaring alias URI families stays interpretive: the plan row
  # holds one exact URI and non-sole-claimant alias families have no
  # plan-side resolution order.
  it "keeps alias-declaring types on the interpretive path" do
    aliased_ns = Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/type-ns/canonical"
      uri_aliases "http://example.com/type-ns/alias"
    end
    stub_const("PlanTypeNsAttr::AliasedNs", aliased_ns)
    type = Class.new(Lutaml::Model::Type::String) do
      include Lutaml::Xml::Type::Configurable

      xml do
        namespace PlanTypeNsAttr::AliasedNs
      end
    end
    stub_const("PlanTypeNsAttr::AliasedValType", type)
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :val, PlanTypeNsAttr::AliasedValType

      xml do
        element "keepNext"
        map_attribute "val", to: :val
      end
    end
    stub_const("PlanTypeNsAttr::AliasedKeepNext", model)

    expect(Lutaml::Xml::Leptris::PlanCompiler.compile(
             model, Lutaml::Model::Config.default_register
           )).to be_nil
  end

  # Engines older than the AttrPlan ns form (libleptris 1.9.289) keep
  # the opt-out — the existing version-gate protocol.
  it "opts out when the engine predates attribute ns rows" do
    allow(Lutaml::Xml::Leptris).to receive(:attr_ns_rows_compatible?)
      .and_return(false)

    expect(Lutaml::Xml::Leptris::PlanCompiler.compile(
             klass, Lutaml::Model::Config.default_register
           )).to be_nil
  end
end
