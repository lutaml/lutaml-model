# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Cross-register embedding on the plan paths (#876)" do
  before do
    stub_const("CrossRegister876", Module.new)
    stub_const("CrossRegister876::Part", part_class)
    stub_const("CrossRegister876::Widget", widget_class)
    stub_const("Host876", host_class)

    ctx = Lutaml::Model::GlobalContext.create_context(
      id: :crossregister876, registry: Lutaml::Model::TypeRegistry.new,
    )
    ctx.registry.register(:part, CrossRegister876::Part)
    ctx.registry.register(:widget, CrossRegister876::Widget)
  end

  let(:part_class) do
    Class.new(Lutaml::Model::Serializable) do
      def self.lutaml_default_register
        :crossregister876
      end

      xml do
        element "part"
      end
    end
  end

  let(:widget_class) do
    klass = Class.new(Lutaml::Model::Serializable) do
      def self.lutaml_default_register
        :crossregister876
      end

      attribute :part_value, :part, collection: true

      xml do
        element "widget"
        ordered
        map_element "part", to: :part_value
      end
    end
    klass
  end

  let(:host_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :widget, CrossRegister876::Widget

      xml do
        element "host"
        map_element "widget", to: :widget
      end
    end
  end

  let(:xml) { "<host><widget><part/></widget></host>" }

  it "resolves the child's symbol types through the child register" do
    model = Host876.from_xml(xml)
    expect(model.widget.part_value.first).to be_a(CrossRegister876::Part)
  end

  it "round-trips through both the plan serializer and back" do
    model = Host876.from_xml(xml)
    xml_out = model.to_xml
    expect(xml_out).to include("<widget>")
    expect(xml_out).to include("<part/>")

    reparsed = Host876.from_xml(xml_out)
    expect(reparsed.widget.part_value.first).to be_a(CrossRegister876::Part)
  end
end
