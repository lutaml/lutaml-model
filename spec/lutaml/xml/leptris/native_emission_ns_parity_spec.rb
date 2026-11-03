# frozen_string_literal: true

# leptris#1941: namespaced trees must emit through the native ops
# lane byte-identically to the DOM lane. The engine's ops builder
# copies each row's ns binding onto the built values and the plan
# serializer collects (prefix, uri) declarations from the result
# tree itself — so the lane's namespace-less restriction was a
# Ruby-side gate, not an engine limit.

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

  let(:instance) { model_class.new(id: "7", value: "hello") }
  let(:register) { Lutaml::Model::Config.default_register }
  let(:plan) { Lutaml::Xml::Leptris::PlanCompiler.compile(model_class, register) }

  it "emits a namespaced tree byte-identically to the DOM lane" do
    native = described_class.emit(instance, plan, register)
    dom = Lutaml::Xml::Leptris::PlanSerializer.call(instance, plan, register)
    expect(native).to eq(dom)
  end

  it "accepts namespaced trees in the compatibility gate" do
    expect(described_class.compatible?(plan)).to be(true)
  end
end
