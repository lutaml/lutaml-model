# frozen_string_literal: true

require "spec_helper"

module ConstructedNs1124
  class WNs < Lutaml::Xml::Namespace
    uri "http://example.com/wordprocessingml"
    prefix_default "w"
    element_form_default :qualified
    attribute_form_default :qualified
  end

  class MNs < Lutaml::Xml::Namespace
    uri "http://example.com/mathml"
    prefix_default "m"
    element_form_default :qualified
    attribute_form_default :qualified
  end

  class MathRun < Lutaml::Model::Serializable
    attribute :text, :string

    xml do
      element "r"
      namespace MNs
      map_element "t", to: :text
    end
  end

  class Para < Lutaml::Model::Serializable
    attribute :runs, MathRun, collection: true

    xml do
      element "p"
      namespace WNs
      map_element "r", to: :runs
    end
  end

  class Body < Lutaml::Model::Serializable
    attribute :paras, Para, collection: true

    xml do
      element "body"
      namespace WNs
      map_element "p", to: :paras
    end
  end
end

RSpec.describe "constructed models serialize foreign namespaces prefixed" do
  # lutaml-model#1124: a constructed (never-parsed) model must serialize
  # child elements in foreign namespaces with their declared prefix,
  # matching the parsed-and-reserialized form — not the default-namespace
  # form. The wire-form signal is attribute qualification: namespaces
  # with attribute_form_default :qualified produce inherently prefixed
  # documents (w: attributes demand the prefix everywhere, root
  # included), so both the w: root and the m: children spell prefixed
  # on the constructed lane exactly as WordprocessingML parts do.

  let(:register) { Lutaml::Model::Config.default_register }

  around do |example|
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  end

  def build_body
    ConstructedNs1124::Body.new(
      paras: [ConstructedNs1124::Para.new(
        runs: [ConstructedNs1124::MathRun.new(text: "x")],
      )],
    )
  end

  it "serializes the constructed model fully prefixed" do
    xml = build_body.to_xml

    expect(xml).to include("<w:body")
    expect(xml).to include("<w:p>")
    expect(xml).to include("<m:r")
    expect(xml).not_to include("<body")
    expect(xml).not_to include("<r>")
  end

  it "round-trips constructed output to the identical form" do
    xml = build_body.to_xml
    reparsed = ConstructedNs1124::Body.from_xml(xml)

    expect(reparsed.to_xml).to eq(xml)
  end

  it "keeps the foreign-namespace child out of the parent's default form" do
    xml = build_body.to_xml

    expect(xml).not_to include('xmlns="http://example.com/mathml"')
  end

  it "routes the multi-namespace unordered emission to the DOM lane" do
    instance = build_body
    plan = Lutaml::Xml::Leptris::PlanCompiler.compile(
      ConstructedNs1124::Body, register
    )

    expect(
      Lutaml::Xml::Leptris::NativeEmission.compatible?(
        plan, instance, register
      ),
    ).to be(false)
  end
end
