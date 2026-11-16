# frozen_string_literal: true

# The uniword clrScheme class of shape: an UNORDERED root whose
# grandchildren defer (each color choice carries an ORDERED srgbClr
# child beside a shared sysClr nested child). Two ways this broke the
# native emission lane before the graph-numbering fix:
#
# - ops against the parse descriptor referenced child plans the
#   compiled tree never materialized (:raw rows carry no plan) — the
#   engine rejected the program (plan result build, INVALID_ARG -5);
# - the per-parent relative-offset layout crossed depth boundaries,
#   sending children of later rows onto earlier rows' plan slots
#   (accent2's slot carrying dk1's sysClr).
#
# The shared SysColor plan (one compiled tree under every color row —
# the [class, register] compile cache) pins the identity-deduped
# numbering both halves depend on.

require "lutaml/model"
require "lutaml/xml/leptris"

RSpec.describe "native emission with nested deferral and shared plans" do
  let(:theme_ns) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/theme"
      prefix_default "a"
    end
  end

  let(:sys_color_class) do
    ns = theme_ns
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :val, :string
      attribute :last_clr, :string

      xml do
        namespace ns
        element "sysClr"
        map_attribute "val", to: :val
        map_attribute "lastClr", to: :last_clr
      end
    end
    stub_const("ClrScheme::SysColor", klass)
    klass
  end

  let(:srgb_color_class) do
    ns = theme_ns
    sys = sys_color_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :val, :string
      attribute :sys, sys

      xml do
        namespace ns
        ordered
        element "srgbClr"
        map_attribute "val", to: :val
        map_element "sysClr", to: :sys
      end
    end
    stub_const("ClrScheme::SrgbColor", klass)
    klass
  end

  let(:color_class) do
    ns = theme_ns
    srgb = srgb_color_class
    sys = sys_color_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :srgb, srgb
      attribute :sys, sys

      xml do
        namespace ns
        element "color"
        map_element "srgbClr", to: :srgb
        map_element "sysClr", to: :sys
      end
    end
    stub_const("ClrScheme::Color", klass)
    klass
  end

  let(:scheme_class) do
    ns = theme_ns
    color = color_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :colors, color, collection: true

      xml do
        namespace ns
        element "clrScheme"
        map_attribute "name", to: :name
        map_element "color", to: :colors
      end
    end
    stub_const("ClrScheme::Scheme", klass)
    klass
  end

  let(:source) do
    colors = %w[dk1 lt1 dk2 lt2 accent1 accent2 accent3 accent4 accent5
                accent6 hlink folHlink].each_with_index.map do |_name, i|
      if i.even?
        %(<a:color><a:srgbClr val="C#{i}"/></a:color>)
      else
        %(<a:color><a:sysClr val="windowText" lastClr="00000#{i}"/></a:color>)
      end
    end.join

    <<~XML
      <a:clrScheme xmlns:a="http://example.com/theme" name="Office">
        #{colors}
      </a:clrScheme>
    XML
  end

  let(:register) { Lutaml::Model::Config.default_register }

  around do |example|
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  end

  it "emits parsed unordered schemes with deferred grandchildren" do
    instance = scheme_class.from_xml(source)
    expect(Lutaml::Xml::Leptris::NativeEmission.compatible?(
             Lutaml::Xml::Leptris::PlanCompiler.compile(scheme_class,
                                                        register),
             instance,
             register,
           )).to be(true)
    xml = instance.to_xml
    expect(xml).to include('val="C0"')
    expect(xml).to include('val="windowText"')
    expect(xml.scan("<a:color>").size).to eq(12)
  end

  it "round-trips every color entry through the emission" do
    instance = scheme_class.from_xml(source)
    restored = scheme_class.from_xml(instance.to_xml)
    expect(restored.name).to eq("Office")
    expect(restored.colors.size).to eq(12)
    expect(restored.colors[0].srgb.val).to eq("C0")
    expect(restored.colors[0].srgb.sys.nil?).to be(true)
    expect(restored.colors[1].sys.val).to eq("windowText")
    expect(restored.colors[1].sys.last_clr).to eq("000001")
    expect(restored.colors[10].srgb.val).to eq("C10")
    expect(restored.colors[11].sys.last_clr).to eq("0000011")
  end
end
