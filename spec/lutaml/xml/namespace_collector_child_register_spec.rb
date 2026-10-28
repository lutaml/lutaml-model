# frozen_string_literal: true

require "spec_helper"

# A nested model may declare its own `lutaml_default_register` (mml does:
# every MathML element class resolves its symbolic child types in the
# per-version MML context). Namespace collection walks the child's XML
# mapping; it must resolve the child's *own* attribute types in the
# child's register, not in the ambient (parent) register.
RSpec.describe "NamespaceCollector nested child model registers" do
  before do
    ctx = Lutaml::Model::GlobalContext.create_context(
      id: :nscollectorchild, registry: Lutaml::Model::TypeRegistry.new,
    )
    ctx.registry.register(:part, widget_part_class)
  end

  let(:widget_part_class) do
    Class.new(Lutaml::Model::Serializable) do
      xml do
        element "part"
      end
    end
  end

  # The symbolic attribute type is declared on a base class; the concrete
  # model is a subclass that carries the register hook. This mirrors
  # Mml::V3::Math < Mml::CommonElements.
  let(:widget_class) do
    Class.new(widget_base_class) do
      def self.lutaml_default_register
        :nscollectorchild
      end
    end
  end

  let(:widget_base_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :part_value, :part, collection: true

      xml do
        element "widget"
        map_element "part", to: :part_value
      end
    end
  end

  let(:host_class) do
    widget = widget_class
    Class.new(Lutaml::Model::Serializable) do
      attribute :widget, widget

      xml do
        element "host"
        map_element "widget", to: :widget
      end
    end
  end

  let(:instance) do
    host_class.from_xml("<host><widget><part/></widget></host>")
  end

  it "resolves the child's symbolic attribute types in the child's register" do
    collector = Lutaml::Xml::NamespaceCollector.new(:default)

    expect do
      collector.collect(instance, host_class.mappings_for(:xml))
    end.not_to raise_error
  end
end
