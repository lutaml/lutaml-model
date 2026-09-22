# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml"

# The plan fast path rides when_attribute partitions (TODO 34 step 2,
# leptris 1.9.221+ #1272 predicate rows): same-name rows claim their
# occurrences exclusively, the plain sibling takes the unclaimed, and
# serialization re-stamps the discriminators. All lanes must agree —
# plan and interpretive — on parse AND round trip, including the
# multi-capture edge (several unclaimed occurrences into a scalar
# attribute arrive as the full array, interpretive parity).
RSpec.describe "Plan fast path with when_attribute partitions" do
  before do
    require "leptris/xml"
  rescue LoadError
    skip "leptris not available"
  end

  let(:model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :a_val, :string
      attribute :b_val, :string
      attribute :other, :string

      xml do
        root "part"
        map_element "item", to: :a_val, when_attribute: { "type" => "a" }
        map_element "item", to: :b_val, when_attribute: { "type" => "b" }
        map_element "item", to: :other
      end
    end
  end

  let(:doc) do
    %(<part><item type="a">A</item><item type="b">B</item><item>plain</item><item type="x">X</item></part>)
  end

  it "compiles the partitioned model with row tags" do
    plan = Lutaml::Xml::PlanCompiler.compile(
      model, Lutaml::Model::Config.default_register
    )
    expect(plan).not_to be_nil
    expect(plan[:row_tags].length).to eq(3)
  end

  it "routes occurrences exclusively and matches the interpretive parse" do
    fast = model.from_xml(doc)
    slow = Lutaml::Model::Config.instance.tap { |c| c.xml_plan_fast_path = false }
      .then { model.from_xml(doc) }
    Lutaml::Model::Config.instance.xml_plan_fast_path = true

    expect(fast.a_val).to eq("A")
    expect(fast.b_val).to eq("B")
    expect(fast.other).to eq(["plain", "X"])
    expect(fast.a_val).to eq(slow.a_val)
    expect(fast.b_val).to eq(slow.b_val)
    expect(fast.other).to eq(slow.other)
  end

  it "round-trips through the serializer with discriminator stamps" do
    round = model.from_xml(model.from_xml(doc).to_xml)
    expect(round.a_val).to eq("A")
    expect(round.b_val).to eq("B")
    expect(round.other).to eq(["plain", "X"])
  end
end
