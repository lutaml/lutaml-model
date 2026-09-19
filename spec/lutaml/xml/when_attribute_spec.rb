# frozen_string_literal: true

require "spec_helper"

# lutaml-model#88: attribute-value dispatch on a shared wire name.
# `map_element "component", to: :guidance, when_attribute: { "type" =>
# "guidance" }` selects only the occurrences whose sibling attribute carries
# the expected value, and re-emits the discriminator on serialization.
class WhenAttrComponent < Lutaml::Model::Serializable
  attribute :text, :string

  xml do
    element "component"
    map_element "text", to: :text
  end
end

class WhenAttrRequirement < Lutaml::Model::Serializable
  attribute :guidance, WhenAttrComponent, collection: true
  attribute :purpose, WhenAttrComponent, collection: true
  attribute :test_method, WhenAttrComponent, collection: true

  xml do
    element "requirement"
    map_element "component", to: :guidance,
                             when_attribute: { "type" => "guidance" }
    map_element "component", to: :purpose,
                             when_attribute: { "type" => "purpose" }
    map_element "component", to: :test_method,
                             when_attribute: { type: "test-method" }
  end
end

RSpec.describe "when_attribute discriminator mappings" do
  before do
    stub_const("WhenAttr::Component", WhenAttrComponent)
    stub_const("WhenAttr::Requirement", WhenAttrRequirement)
  end

  let(:xml) do
    <<~XML
      <requirement>
        <component type="guidance"><text>g1</text></component>
        <component type="purpose"><text>p1</text></component>
        <component type="guidance"><text>g2</text></component>
        <component type="test-method"><text>t1</text></component>
      </requirement>
    XML
  end

  it "dispatches occurrences by the discriminator value" do
    req = WhenAttr::Requirement.from_xml(xml)

    expect(req.guidance.map(&:text)).to eq(%w[g1 g2])
    expect(req.purpose.map(&:text)).to eq(["p1"])
    expect(req.test_method.map(&:text)).to eq(["t1"])
  end

  it "keeps document order within each target attribute" do
    req = WhenAttr::Requirement.from_xml(xml)
    expect(req.guidance.map(&:text)).to eq(%w[g1 g2])
  end

  it "drops occurrences whose discriminator is not covered" do
    doc = '<requirement><component type="unknown"><text>x</text></component></requirement>'
    req = WhenAttr::Requirement.from_xml(doc)

    expect(req.guidance).to be_empty
    expect(req.purpose).to be_empty
  end

  it "re-emits the discriminator attribute on serialization" do
    round = WhenAttr::Requirement.from_xml(WhenAttr::Requirement.from_xml(xml).to_xml)

    expect(round.guidance.map(&:text)).to eq(%w[g1 g2])
    expect(round.purpose.map(&:text)).to eq(["p1"])
    expect(round.test_method.map(&:text)).to eq(["t1"])

    serialized = WhenAttr::Requirement.from_xml(xml).to_xml
    expect(serialized).to include('type="guidance"')
    expect(serialized).to include('type="purpose"')
    expect(serialized).to include('type="test-method"')
  end

  it "does not emit a discriminator for ordinary rules" do
    plain = Class.new(Lutaml::Model::Serializable) do
      attribute :text, :string

      xml do
        element "plain"
        map_element "text", to: :text
      end
    end

    expect(plain.from_xml("<plain><text>t</text></plain>").to_xml)
      .not_to include("type=")
  end

  it "survives deep_dup of mappings" do
    mapping = WhenAttr::Requirement.mappings_for(:xml)
    duped = mapping.deep_dup.mappings.find do |r|
      r.to == :guidance
    end

    expect(duped.when_attribute).to eq("type" => "guidance")
  end

  it "rejects non-string/symbol discriminator shapes" do
    expect do
      Class.new(Lutaml::Model::Serializable) do
        attribute :x, :string

        xml do
          element "x"
          map_element "x", to: :x, when_attribute: { "type" => 42 }
        end
      end
    end.to raise_error(Lutaml::Model::IncorrectMappingArgumentsError, /when_attribute/)
  end

  it "is rejected on attribute mappings" do
    expect do
      Class.new(Lutaml::Model::Serializable) do
        attribute :x, :string

        xml do
          element "x"
          map_attribute "x", to: :x, when_attribute: { "type" => "guidance" }
        end
      end
    end.to raise_error(ArgumentError)
  end
end
