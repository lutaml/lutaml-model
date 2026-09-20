# frozen_string_literal: true

require "spec_helper"

# lutaml-model#88: `when_attribute` partitioning under `ordered` mappings.
# The ordered walk routes each element_order entry by its recorded
# attributes, so `<component type="guidance">` and `<component
# type="purpose">` interleave on to_xml exactly as the source document did.
class WhenOrderedComponent < Lutaml::Model::Serializable
  attribute :text, :string

  xml do
    element "component"
    map_element "text", to: :text
  end
end

class WhenOrderedRequirement < Lutaml::Model::Serializable
  attribute :guidance, WhenOrderedComponent, collection: true
  attribute :purpose, WhenOrderedComponent, collection: true
  attribute :test_method, WhenOrderedComponent, collection: true

  xml do
    element "requirement"
    ordered
    map_element "component", to: :guidance,
                             when_attribute: { "type" => "guidance" }
    map_element "component", to: :purpose,
                             when_attribute: { "type" => "purpose" }
    map_element "component", to: :test_method,
                             when_attribute: { type: "test-method" }
  end
end

RSpec.describe "when_attribute under ordered mappings" do
  before do
    stub_const("WhenOrdered::Component", WhenOrderedComponent)
    stub_const("WhenOrdered::Requirement", WhenOrderedRequirement)
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

  def serialized_types(doc)
    doc.scan(/<component type="([^"]+)">/).flatten
  end

  it "parses partitioned values" do
    req = WhenOrderedRequirement.from_xml(xml)

    expect(req.guidance.map(&:text)).to eq(%w[g1 g2])
    expect(req.purpose.map(&:text)).to eq(["p1"])
    expect(req.test_method.map(&:text)).to eq(["t1"])
  end

  it "records the discriminator attributes on element_order entries" do
    req = WhenOrderedRequirement.from_xml(xml)
    entries = req.element_order.select { |e| e.type == "Element" }

    expect(entries.map(&:attributes)).to eq([
                                              { "type" => "guidance" },
                                              { "type" => "purpose" },
                                              { "type" => "guidance" },
                                              { "type" => "test-method" },
                                            ])
  end

  it "round-trips the original interleaving" do
    round = WhenOrderedRequirement.from_xml(xml).to_xml

    expect(serialized_types(round)).to eq(
      %w[guidance purpose guidance test-method],
    )
  end

  it "survives a re-parse of the ordered output" do
    once = WhenOrderedRequirement.from_xml(xml)
    twice = WhenOrderedRequirement.from_xml(once.to_xml)

    expect(twice.guidance.map(&:text)).to eq(%w[g1 g2])
    expect(twice.purpose.map(&:text)).to eq(["p1"])
    expect(twice.test_method.map(&:text)).to eq(["t1"])
  end

  it "routes appended items to the right attribute on ordered output" do
    req = WhenOrderedRequirement.from_xml(xml)
    req.guidance << WhenOrderedComponent.new(text: "g3")

    out = req.to_xml
    # Reconciliation places new entries after the rule's last existing
    # occurrence (the OrderReconciler contract), not at document end.
    expect(serialized_types(out)).to eq(
      %w[guidance purpose guidance guidance test-method],
    )

    reparsed = WhenOrderedRequirement.from_xml(out)
    expect(reparsed.guidance.map(&:text)).to eq(%w[g1 g2 g3])
    expect(reparsed.purpose.map(&:text)).to eq(["p1"])
  end

  it "drops occurrences with an unknown discriminator from ordered output" do
    with_unknown = WhenOrderedRequirement.from_xml(<<~XML)
      <requirement>
        <component type="guidance"><text>g1</text></component>
        <component type="unknown"><text>x</text></component>
        <component type="purpose"><text>p1</text></component>
      </requirement>
    XML

    expect(with_unknown.guidance.map(&:text)).to eq(["g1"])
    expect(with_unknown.purpose.map(&:text)).to eq(["p1"])
    expect(serialized_types(with_unknown.to_xml)).to eq(%w[guidance purpose])
  end

  it "falls back to the plain rule for legacy attribute-less entries" do
    both = Class.new(Lutaml::Model::Serializable) do
      attribute :plain, :string
      attribute :special, :string

      xml do
        element "holder"
        ordered
        map_element "item", to: :plain
        map_element "item", to: :special, when_attribute: { "kind" => "special" }
      end
    end
    stub_const("WhenOrdered::Holder", both)

    doc = both.from_xml(
      "<holder><item>a</item><item kind=\"special\">b</item></holder>",
    )

    expect(doc.plain).to eq("a")
    expect(doc.special).to eq("b")

    out = doc.to_xml
    expect(out.scan(%r{<item[^>]*>([^<]*)</item>})).to eq([["a"], ["b"]])
    expect(out).to include('kind="special"')
  end
end
