# frozen_string_literal: true

# leptris#1941 ordered slice: parsed ordered models — the uniword
# shape (element-only roots, nested ordered paragraphs, mixed-content
# runs) — emit through the native ops lane byte-identically to the
# interpretive writer. The DOM lane mints one wrapper per element
# (create_element + Class#new ≈ 14% of serialize CPU plus its GC
# share); the ops lane pushes rows and lets the engine build.

require "lutaml/model"
require "lutaml/xml/leptris"

RSpec.describe Lutaml::Xml::Leptris::NativeEmission do
  let(:w_ns) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/ordered/wml"
      prefix_default "w"
    end
  end

  let(:t_class) do
    ns = w_ns
    stub_const("OrderedNs::WmlNs", ns)
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :value, :string

      xml do
        namespace ns
        element "t"
        map_content to: :value
      end
    end
    stub_const("OrderedNs::T", klass)
    klass
  end

  let(:run_class) do
    t_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :bold, :boolean
      attribute :ts, OrderedNs::T, collection: true

      xml do
        namespace OrderedNs::WmlNs
        ordered
        element "r"
        map_attribute "bold", to: :bold
        map_element "t", to: :ts
      end
    end
    stub_const("OrderedNs::Run", klass)
    klass
  end

  let(:para_class) do
    run_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :style, :string
      attribute :runs, OrderedNs::Run, collection: true

      xml do
        namespace OrderedNs::WmlNs
        ordered
        element "p"
        map_attribute "style", to: :style
        map_element "r", to: :runs
      end
    end
    stub_const("OrderedNs::Para", klass)
    klass
  end

  let(:doc_class) do
    para_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :paras, OrderedNs::Para, collection: true

      xml do
        namespace OrderedNs::WmlNs
        ordered
        element "document"
        map_element "p", to: :paras
      end
    end
    stub_const("OrderedNs::Document", klass)
    klass
  end

  let(:source) do
    <<~XML
      <w:document xmlns:w="http://example.com/ordered/wml">
        <w:p style="Heading1">
          <w:r><w:t>first run</w:t></w:r>
          <w:r w:bold="true"><w:t>second</w:t></w:r>
        </w:p>
        <w:p>
          <w:r><w:t>plain</w:t></w:r>
        </w:p>
      </w:document>
    XML
  end
  let(:register) { Lutaml::Model::Config.default_register }
  let(:instance) { doc_class.from_xml(source) }
  let(:plan) do
    Lutaml::Xml::Leptris::PlanCompiler.compile(doc_class, register)
  end

  around do |example|
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  end

  it "admits parsed ordered instances in the compatibility gate" do
    expect(described_class.compatible?(plan, instance, register)).to be(true)
  end

  it "emits ordered parsed instances byte-identically to the interpretive writer" do
    _p = plan
    _i = instance
    Lutaml::Xml::Leptris::PlanCompiler.compile(OrderedNs::Para, register)
    
    
    
    
    
    
    native = described_class.emit(instance, plan, register)
    
    interpretive = Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      instance.to_xml
    end
    expect(native).to eq(interpretive)
  end

  it "round-trips the emitted document" do
    native = described_class.emit(instance, plan, register)
    reparsed = doc_class.from_xml(native)
    expect(reparsed.paras.size).to eq(2)
    expect(reparsed.paras[0].runs.map { |r| r.ts.map(&:value) }).to eq(
      [["first run"], ["second"]],
    )
    expect(reparsed.paras[0].runs[1].bold).to be(true)
    expect(reparsed.paras[1].runs.first.ts.first.value).to eq("plain")
  end
end
