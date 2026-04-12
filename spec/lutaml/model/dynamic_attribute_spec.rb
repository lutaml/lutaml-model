# frozen_string_literal: true

require "spec_helper"

# Namespace classes for dynamic attribute specs
class DynAttrTestNamespace < Lutaml::Xml::W3c::XmlNamespace
  uri "http://example.com/dyn-attr-test"
  prefix_default "dat"
  element_form_default :qualified
end

RSpec.describe "Dynamic attribute addition after register imports" do
  # This spec guards against a regression where the `attribute` method wrote to
  # a temporary merged hash instead of `@attributes` when `@register_records`
  # was populated. This caused dynamically-added attributes (e.g., via
  # class_eval after load_extension) to be silently lost.
  #
  # The root cause: `attribute` method called `attributes[name] = attr` which
  # invokes the `attributes()` accessor. When `@register_records` has entries,
  # `attributes()` returns `@attributes.merge(...)` (a NEW hash), so the
  # assignment went to a discarded temporary copy.

  let(:register) do
    Lutaml::Model::Register.new(:dyn_attr_test_reg,
                                fallback: [:default]).tap do |reg|
      reg.bind_namespace(DynAttrTestNamespace)
    end
  end

  let(:base_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      xml do
        root "BaseModel"
        namespace DynAttrTestNamespace
        map_element "Name", to: :name
      end
    end
  end

  let(:extension_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :code, :string

      xml do
        root "ExtensionModel"
        namespace DynAttrTestNamespace
        map_element "Code", to: :code
      end
    end
  end

  before do
    Lutaml::Model::GlobalContext.reset!
  end

  it "allows adding attributes after register_records are populated" do
    # Step 1: Register and import to populate @register_records
    register.register_model(extension_model, id: :extension_model)
    base_model.import_model_attributes(extension_model, register.id)

    expect(base_model.instance_variable_get(:@register_records)).not_to be_empty

    # Step 2: Dynamically add a new attribute via class_eval (simulates
    # runtime extension loading after initial parsing)
    base_model.class_eval do
      attribute :dynamic_field, :string
    end

    # The attribute must be persisted in @attributes
    expect(base_model.instance_variable_get(:@attributes)).to have_key(:dynamic_field)
    expect(base_model.attributes).to have_key(:dynamic_field)
  end

  it "persists dynamically-added attributes when accessed via register" do
    # Populate register_records by importing
    register.register_model(extension_model, id: :extension_model)
    base_model.import_model_attributes(extension_model, register.id)

    # Add attribute dynamically
    base_model.class_eval do
      attribute :extra, :string
    end

    # attributes(register) must include the dynamic attribute
    expect(base_model.attributes(register.id)).to have_key(:extra)
    expect(base_model.attributes(register.id)[:extra].name).to eq(:extra)
  end

  it "does not lose attributes added between parses" do
    register.register_model(base_model, id: :base_model)

    xml1 = <<~XML
      <dat:BaseModel xmlns:dat="http://example.com/dyn-attr-test">
        <dat:Name>first</dat:Name>
      </dat:BaseModel>
    XML

    # First parse populates @register_records via ensure_imports!
    base_model.from_xml(xml1, register: register)

    # Now dynamically add an attribute (simulates runtime extension loading)
    base_model.class_eval do
      attribute :added_later, :string
    end

    # The attribute must be persisted
    expect(base_model.attributes).to have_key(:added_later)
    expect(base_model.instance_variable_get(:@attributes)).to have_key(:added_later)
  end
end
