# frozen_string_literal: true

# The native emission lane must honor render_default: false the way
# the DOM lane does: an attribute whose value came from the default
# cast (using_default?) - e.g. a parse that omitted the attribute and
# a value type that casts nil to a concrete value - stays unwritten.
# Without the gate, a parsed w:style without w:default round-trips
# with a ghost w:default="0" (uniword Style, lutaml-model#1136).

require "lutaml/model"
require "lutaml/xml/leptris"
require "leptris/xml/ffi"

# uniword's OoxmlBoolean semantics: an omitted attribute casts nil to
# a CONCRETE false, which is what makes the ghost emission visible (a
# non-nil value reaches the lane).
class StOnOffBoolean < Lutaml::Model::Type::Boolean # rubocop:disable Naming/PredicateMethod
  ON = [true, "1", "true"].freeze

  def self.cast(value, _options = {}) # rubocop:disable Naming/PredicateMethod
    return false if value.nil?

    ON.include?(value)
  end

  def self.serialize(value)
    return nil if value.nil?
    return "1" if ON.include?(value)

    "0"
  end
end

RSpec.describe Lutaml::Xml::Leptris::NativeEmission do
  let(:w_namespace) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://example.com/wordprocessingml"
      prefix_default "w"
      element_form_default :qualified
      attribute_form_default :qualified
    end
  end

  let(:on_off_type) { StOnOffBoolean }

  let(:model_class) do
    ns = w_namespace
    flag = on_off_type
    Class.new do
      include Lutaml::Model::Serialize

      attribute :flag, flag
      attribute :custom, flag
      attribute :kind, :string
      attribute :name, :string
      attribute :base, :string

      xml do
        namespace ns
        element "style"
        map_attribute "kind", to: :kind, render_nil: false
        map_attribute "flag", to: :flag, render_default: false,
                              render_nil: false
        map_attribute "custom", to: :custom, render_default: false
        map_element "name", to: :name, render_nil: false
        map_element "base", to: :base, render_nil: false

        def self.name
          "RenderDefaultModel"
        end
      end
    end
  end

  let(:register) { Lutaml::Model::Config.default_register }
  let(:plan) { Lutaml::Xml::Leptris::PlanCompiler.compile(model_class, register) }

  it "keeps a parse-omitted attribute unwritten on the recorded path" do
    source = '<w:style xmlns:w="http://example.com/wordprocessingml" ' \
             'w:kind="paragraph"><w:name>H1</w:name>' \
             "<w:base>Normal</w:base></w:style>"
    instance = model_class.from_xml(source)

    xml = instance.to_xml

    expect(xml).not_to include("w:flag")
    expect(xml).not_to include("w:custom")
    expect(xml).to include("w:kind=")
    expect(xml).to include("H1")
  end

  it "emits an explicitly-set false on the recorded path" do
    source = '<w:style xmlns:w="http://example.com/wordprocessingml" ' \
             'w:flag="0"><w:name>H1</w:name></w:style>'
    instance = model_class.from_xml(source)

    xml = instance.to_xml

    expect(xml).to include("w:flag=")
    expect(xml).to include("H1")
  end
end
