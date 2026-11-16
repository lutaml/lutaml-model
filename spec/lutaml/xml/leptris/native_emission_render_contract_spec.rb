# frozen_string_literal: true

# lutaml-model#1136: the native emission lane ignored the DOM lane's
# render contract for attributes — an attribute whose value is still
# the default (a parse that omitted it from the source) must not
# emit when the mapping declares render_default: false. uniword's
# Style round-trip caught it: a parsed style without w:default came
# back with the ghost `w:default="0"` (the custom boolean type's
# serialization of its default).

require "lutaml/model"
require "lutaml/xml/leptris"

RSpec.describe "native emission honors the attribute render contract" do
  let(:flag_type) do
    Class.new(Lutaml::Model::Type::Value) do
      def self.cast(value)
        return true if ["1", true].include?(value)
        return false if ["0", false].include?(value)

        value
      end

      def serialize(_format, _register = nil)
        self.class.cast(@value) ? "1" : "0"
      end

      def self.name
        "EmissionRenderFlag"
      end
    end
  end

  let(:model_class) do
    flag = flag_type
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :default, flag
      attribute :custom_style, flag

      xml do
        element "style"
        map_attribute "name", to: :name
        map_attribute "default", to: :default, render_default: false,
                                 render_nil: false
        map_attribute "customStyle", to: :custom_style,
                                     render_default: false
      end

      def self.name
        "EmissionRenderStyle"
      end
    end
    stub_const("EmissionRender::Style", klass)
    klass
  end

  let(:source) do
    '<style xmlns="http://example.com/style" name="H1"/>'
  end

  around do |example|
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  end

  it "omits parsed-omitted attributes that carry render_default: false" do
    instance = model_class.from_xml(source)
    xml = instance.to_xml
    expect(xml).to include("name=\"H1\"")
    expect(xml).not_to include("default")
    expect(xml).not_to include("customStyle")
  end

  it "still emits attributes the source actually carried" do
    xml = model_class.from_xml(
      '<style xmlns="http://example.com/style" name="H1" default="1"/>',
    ).to_xml
    expect(xml).to include("default=")
  end

  it "keeps the DOM lane's contract on the recorded-order path" do
    instance = model_class.from_xml(
      '<style xmlns="http://example.com/style" customStyle="1" name="A"/>',
    )
    xml = instance.to_xml
    expect(xml).to include("customStyle=")
    expect(xml).not_to include("default=")
  end
end
