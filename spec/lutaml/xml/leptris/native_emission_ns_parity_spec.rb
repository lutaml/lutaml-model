# frozen_string_literal: true

# The engine's ops lane spells prefix:local for every EXACT row and
# cannot express the default-xmlns form — so namespaced trees ride
# the lane only under a prefixed-preserved root (Priority 1 format
# preservation; the DOM lane inherits the root prefix down the
# tree). Constructed and default-parsed roots pin the default-xmlns
# form and MUST take the DOM lane (uniword bold/custprops format
# regressions when the lane admitted them).

require "lutaml/model"
require "lutaml/xml/leptris"
require "leptris/xml/ffi"

RSpec.describe Lutaml::Xml::Leptris::NativeEmission do
  let(:ex_namespace) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://example.com/ns"
      prefix_default "ex"
    end
  end

  let(:model_class) do
    ns = ex_namespace
    Class.new do
      include Lutaml::Model::Serialize

      attribute :id, :string
      attribute :value, :string

      xml do
        namespace ns
        element "element"
        map_element "id", to: :id
        map_element "value", to: :value
      end

      def self.name
        "NsEmissionModel"
      end
    end
  end

  let(:register) { Lutaml::Model::Config.default_register }
  let(:plan) { Lutaml::Xml::Leptris::PlanCompiler.compile(model_class, register) }

  it "rejects a constructed namespaced tree in the compatibility gate" do
    expect(described_class.compatible?(plan)).to be(false)
  end

  it "serializes constructed namespaced models in the default-xmlns format" do
    xml = model_class.new(id: "7", value: "hello").to_xml
    expect(xml).to include('<element xmlns="http://example.com/ns"')
    expect(xml).not_to include("ex:")
  end

  it "admits a namespaced tree under a prefixed-preserved root" do
    source = '<ex:element xmlns:ex="http://example.com/ns">' \
             "<ex:id>7</ex:id><ex:value>hello</ex:value></ex:element>"
    instance = model_class.from_xml(source)
    expect(instance.xml_namespace_prefix).to eq("ex")
    expect(described_class.compatible?(plan, instance, register)).to be(true)
    native = described_class.emit(instance, plan, register)
    expect(native).to include("ex:element")
    reparsed = model_class.from_xml(native)
    expect(reparsed.id).to eq("7")
    expect(reparsed.value).to eq("hello")
  end
end
