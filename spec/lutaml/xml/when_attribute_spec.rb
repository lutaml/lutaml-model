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

  # Orthogonality guard: `when_attribute` partitions occurrences across
  # attributes; `polymorphic` dispatches the class of each hydrated item.
  # Different axes over the same discriminator concept — they compose on
  # one rule rather than substitute for each other.
  describe "vs polymorphic dispatch" do
    before do
      stub_const("AxisComp", Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string
      end)
      stub_const("AxisGuidanceComp", Class.new(AxisComp))
      stub_const("AxisPurposeComp", Class.new(AxisComp))
    end

    let(:axes_xml) do
      <<~XML
        <req>
          <component type="guidance"><text>g1</text></component>
          <component type="purpose"><text>p1</text></component>
          <component type="guidance"><text>g2</text></component>
        </req>
      XML
    end

    it "polymorphic keeps one attribute and dispatches classes" do
      poly = Class.new(Lutaml::Model::Serializable) do
        attribute :components, AxisComp, collection: true

        xml do
          element "req"
          map_element "component", to: :components, polymorphic: {
            attribute: "type",
            class_map: {
              "guidance" => "AxisGuidanceComp",
              "purpose" => "AxisPurposeComp",
            },
          }
        end
      end

      parsed = poly.from_xml(axes_xml)
      expect(parsed.components.map(&:class))
        .to eq([AxisGuidanceComp, AxisPurposeComp, AxisGuidanceComp])
    end

    it "when_attribute keeps one class and partitions attributes" do
      partitioned = Class.new(Lutaml::Model::Serializable) do
        attribute :guidance, AxisComp, collection: true
        attribute :purpose, AxisComp, collection: true

        xml do
          element "req"
          map_element "component", to: :guidance,
                                   when_attribute: { "type" => "guidance" }
          map_element "component", to: :purpose,
                                   when_attribute: { "type" => "purpose" }
        end
      end

      parsed = partitioned.from_xml(axes_xml)
      expect(parsed.guidance.map(&:text)).to eq(%w[g1 g2])
      expect(parsed.purpose.map(&:text)).to eq(["p1"])
      expect(parsed.guidance.first.class).to eq(AxisComp)
    end

    it "composes: partition and class dispatch on the same rule" do
      both = Class.new(Lutaml::Model::Serializable) do
        attribute :guidance, AxisComp, collection: true
        attribute :purpose, AxisComp, collection: true

        xml do
          element "req"
          map_element "component", to: :guidance,
                                   when_attribute: { "type" => "guidance" },
                                   polymorphic: {
                                     attribute: "type",
                                     class_map: { "guidance" => "AxisGuidanceComp" },
                                   }
          map_element "component", to: :purpose,
                                   when_attribute: { "type" => "purpose" },
                                   polymorphic: {
                                     attribute: "type",
                                     class_map: { "purpose" => "AxisPurposeComp" },
                                   }
        end
      end

      parsed = both.from_xml(axes_xml)
      expect(parsed.guidance.map(&:class)).to eq([AxisGuidanceComp, AxisGuidanceComp])
      expect(parsed.purpose.map(&:class)).to eq([AxisPurposeComp])
    end
  end
end
