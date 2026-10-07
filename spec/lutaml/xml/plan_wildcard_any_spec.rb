# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML plan fast path: map_any_element catch-all" do
  # leptris#1552: the wildcard child row rides a two-pass walk where
  # named rows take precedence; the hydrator bridges the unclaimed
  # remainder in document order and casts it through the attribute —
  # the interpretive pass's contract for map_any_element.

  let(:host_class) do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :title, :string
      attribute :others, :string, collection: true

      xml do
        element "host"
        map_element "title", to: :title
        map_any_element to: :others
      end
    end
    stub_const("Gate4Any::Host", klass)
    klass
  end

  let(:typed_class) do
    item = Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string

      xml do
        element "item"
        map_content to: :content
      end
    end
    stub_const("Gate4Any::Item", item)
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :label, :string
      attribute :items, Gate4Any::Item, collection: true

      xml do
        element "bag"
        map_element "label", to: :label
        map_any_element to: :items
      end
    end
    stub_const("Gate4Any::Bag", model)
    model
  end

  around do |example|
    old = Lutaml::Model::Config.instance.xml_plan_fast_path
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = old
  end

  # Members flow through the attribute's cast exactly as the
  # interpretive pass does: String attributes stringify the wrapper
  # (both paths identically), Serializable attributes build instances.
  def member_shapes(elements)
    elements.map { |e| e.class.name.split("::").last }
  end

  it "captures unclaimed children in document order" do
    doc = "<host><title>t</title><extra1>a</extra1>" \
          "<extra2>b</extra2></host>"

    parsed = host_class.from_xml(doc)
    expect(parsed.title).to eq("t")
    expect(parsed.others.size).to eq(2)
    expect(member_shapes(parsed.others)).to eq(%w[String String])
  end

  it "captures typed members as model instances" do
    doc = "<bag><label>L</label><item>one</item><item>two</item></bag>"

    parsed = typed_class.from_xml(doc)
    expect(parsed.label).to eq("L")
    expect(parsed.items.map(&:content)).to eq(%w[one two])
  end

  it "matches the interpretive path's capture" do
    doc = "<host><title>t</title><extra1>a</extra1><extra2>b</extra2></host>"

    interpretive = Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      host_class.from_xml(doc)
    end

    parsed = host_class.from_xml(doc)
    expect(parsed.others.size).to eq(interpretive.others.size)
    expect(member_shapes(parsed.others)).to eq(
      member_shapes(interpretive.others).map { |n| n.sub("Nokogiri", "Leptris") },
    )
  end

  it "compiles under engines without wildcard rows to nil" do
    allow(Lutaml::Xml::Leptris).to receive(:wildcard_rows_compatible?)
      .and_return(false)

    expect(Lutaml::Xml::Leptris::PlanCompiler.compile(
             host_class, Lutaml::Model::Config.default_register
           )).to be_nil
  end
end
