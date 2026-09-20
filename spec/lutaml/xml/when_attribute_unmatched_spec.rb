# frozen_string_literal: true

require "spec_helper"

# lutaml-model#88: `unmatched: :raise` on a when_attribute rule fails the
# parse when an occurrence is claimed by no rule — no discriminator match
# and no plain sibling on the wire name. The default (:drop) keeps the
# silent-drop behavior.
class UnmatchedComponent < Lutaml::Model::Serializable
  attribute :text, :string

  xml do
    element "component"
    map_element "text", to: :text
  end
end

class UnmatchedRequirement < Lutaml::Model::Serializable
  attribute :guidance, UnmatchedComponent, collection: true
  attribute :purpose, UnmatchedComponent, collection: true

  xml do
    element "requirement"
    map_element "component", to: :guidance,
                             when_attribute: { "type" => "guidance" },
                             unmatched: :raise
    map_element "component", to: :purpose,
                             when_attribute: { "type" => "purpose" }
  end
end

RSpec.describe "when_attribute unmatched policy" do
  before do
    stub_const("Unmatched::Component", UnmatchedComponent)
    stub_const("Unmatched::Requirement", UnmatchedRequirement)
  end

  it "parses when every occurrence is covered" do
    req = UnmatchedRequirement.from_xml(<<~XML)
      <requirement>
        <component type="guidance"><text>g1</text></component>
        <component type="purpose"><text>p1</text></component>
      </requirement>
    XML

    expect(req.guidance.map(&:text)).to eq(["g1"])
    expect(req.purpose.map(&:text)).to eq(["p1"])
  end

  it "raises on an unknown discriminator value" do
    xml = <<~XML
      <requirement>
        <component type="guidance"><text>g1</text></component>
        <component type="unknown"><text>x</text></component>
      </requirement>
    XML

    expect { UnmatchedRequirement.from_xml(xml) }
      .to raise_error(Lutaml::Model::UnknownDiscriminatorError, /type="unknown"/)
  end

  it "raises when the discriminator attribute is missing entirely" do
    xml = "<requirement><component><text>x</text></component></requirement>"

    expect { UnmatchedRequirement.from_xml(xml) }
      .to raise_error(Lutaml::Model::UnknownDiscriminatorError, /<component>/)
  end

  it "names the tested attributes of the unclaimed occurrence" do
    xml = '<requirement><component type="later"><text>x</text></component></requirement>'

    expect { UnmatchedRequirement.from_xml(xml) }
      .to raise_error(Lutaml::Model::UnknownDiscriminatorError, /unmatched: :drop/)
  end

  it "does not raise when a plain rule claims the leftovers" do
    both = Class.new(Lutaml::Model::Serializable) do
      attribute :special, UnmatchedComponent, collection: true
      attribute :plain, UnmatchedComponent, collection: true

      xml do
        element "holder"
        map_element "item", to: :special,
                            when_attribute: { "kind" => "special" },
                            unmatched: :raise
        map_element "item", to: :plain
      end
    end
    stub_const("Unmatched::Holder", both)

    doc = both.from_xml(
      '<holder><item kind="special"><text>b</text></item><item><text>a</text></item></holder>',
    )

    expect(doc.special.map(&:text)).to eq(["b"])
    expect(doc.plain.map(&:text)).to eq(["a"])
  end

  it "drops unmatched occurrences by default" do
    lenient = Class.new(Lutaml::Model::Serializable) do
      attribute :guidance, UnmatchedComponent, collection: true

      xml do
        element "requirement"
        map_element "component", to: :guidance,
                                 when_attribute: { "type" => "guidance" }
      end
    end
    stub_const("Unmatched::Lenient", lenient)

    doc = lenient.from_xml(
      '<requirement><component type="guidance"><text>g</text></component>' \
      '<component type="other"><text>x</text></component></requirement>',
    )
    expect(doc.guidance.map(&:text)).to eq(["g"])
  end

  it "survives deep_dup of mappings" do
    rule = UnmatchedRequirement.mappings_for(:xml).mappings.find do |r|
      r.to == :guidance
    end

    expect(rule.unmatched).to eq(:raise)
    duped = rule.deep_dup
    expect(duped.unmatched).to eq(:raise)
    expect(duped.when_attribute).to eq("type" => "guidance")
  end

  it "rejects unknown policy values" do
    expect do
      Class.new(Lutaml::Model::Serializable) do
        attribute :x, :string

        xml do
          element "x"
          map_element "x", to: :x,
                           when_attribute: { "type" => "a" },
                           unmatched: :explode
        end
      end
    end.to raise_error(Lutaml::Model::IncorrectMappingArgumentsError, /unmatched/)
  end

  it "rejects unmatched without when_attribute" do
    expect do
      Class.new(Lutaml::Model::Serializable) do
        attribute :x, :string

        xml do
          element "x"
          map_element "x", to: :x, unmatched: :raise
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
          map_attribute "x", to: :x, unmatched: :raise
        end
      end
    end.to raise_error(ArgumentError)
  end
end
