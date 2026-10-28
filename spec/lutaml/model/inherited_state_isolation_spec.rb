# frozen_string_literal: true

require_relative "../../spec_helper"

# Pin the inheritance-state isolation contract between a model class, its
# superclass and its siblings. These are the semantics the eager copy in
# `initialize_attrs` has always provided; they must hold for any
# copy-on-write replacement of that copy.
RSpec.describe "inherited model state isolation" do
  let(:parent) do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :size, :integer

      xml do
        element "parent"
        map_attribute "name", to: :name
        map_element "size", to: :size
      end
    end
    stub_const("IsoParent", klass)
    klass
  end

  it "gives the child the parent's attributes and mappings immediately" do
    child = Class.new(parent)
    stub_const("IsoChildSeen", child)

    expect(IsoChildSeen.attributes.key?(:name)).to be(true)
    expect(IsoChildSeen.attributes.key?(:size)).to be(true)
    expect(IsoChildSeen.mappings[:xml].elements_hash).not_to be_empty
  end

  it "hides a child's attribute declaration from the parent" do
    child = Class.new(parent) do
      attribute :extra, :string
    end
    stub_const("IsoChildExtra", child)

    expect(IsoChildExtra.attributes.key?(:extra)).to be(true)
    expect(parent.attributes.key?(:extra)).to be(false)
  end

  it "hides a child's mapping declaration from the parent" do
    child = Class.new(parent) do
      attribute :extra, :string
      xml do
        map_element "extra", to: :extra
      end
    end
    stub_const("IsoChildMapping", child)

    model = child.new(name: "x", extra: "e")
    expect(model.to_xml).to include("<extra>e</extra>")
    expect(parent.mappings[:xml].elements_hash.key?("extra")).to be(false)
  end

  it "hides a parent attribute declared after subclassing from the child" do
    child = Class.new(parent)
    stub_const("IsoChildLateParent", child)

    parent.attribute :late, :string

    expect(parent.attributes.key?(:late)).to be(true)
    expect(child.attributes.key?(:late)).to be(false)
  end

  it "hides a parent mapping declared after subclassing from the child" do
    child = Class.new(parent) do
      attribute :late_element, :string
    end
    stub_const("IsoChildLateMapping", child)

    parent.xml do
      map_element "late_element", to: :late_element
    end

    expect(parent.mappings[:xml].elements_hash.key?("late_element")).to be(true)
    expect(child.mappings[:xml].elements_hash.key?("late_element")).to be(false)
  end

  it "isolates restrict between parent, child and sibling" do
    child_a = Class.new(parent)
    stub_const("IsoRestrictA", child_a)
    child_b = Class.new(parent)
    stub_const("IsoRestrictB", child_b)

    child_a.restrict :name, default: "a-default"
    parent.restrict :size, default: 42

    expect(parent.attributes[:name].default).to eq(IsoRestrictB.attributes[:name].default)
    expect(IsoRestrictA.attributes[:name].default).to eq("a-default")
    expect(IsoRestrictB.attributes[:size].default).not_to eq(42)
    expect(IsoRestrictA.attributes[:size].default).not_to eq(42)
  end

  it "isolates choice declarations from the parent" do
    child = Class.new(parent) do
      choice(min: 0, max: 1) do
        attribute :a, :string
        attribute :b, :string
      end
    end
    stub_const("IsoChoiceChild", child)

    expect(child.choice_attributes.size).to eq(1)
    expect(parent.choice_attributes).to be_empty
  end

  it "isolates a register-only import from the parent" do
    source = Class.new(Lutaml::Model::Serializable) do
      attribute :imported, :string
    end
    stub_const("IsoImportSource", source)

    child = Class.new(parent) do
      xml do
        element "child"
        map_attribute "name", to: :name
      end
      import_model IsoImportSource, :custom_reg
    end
    stub_const("IsoImportChild", child)

    expect(child.register_record(:custom_reg)[:attributes].key?(:imported))
      .to be(true)
    expect(parent.register_record(:custom_reg)[:attributes]).to be_empty
    expect(source.attributes.key?(:imported)).to be(true)
  end

  it "keeps a default-register import out of the parent" do
    source = Class.new(Lutaml::Model::Serializable) do
      attribute :def_imported, :string
    end
    stub_const("IsoImportDefaultSource", source)

    child = Class.new(parent) do
      import_model IsoImportDefaultSource
    end
    stub_const("IsoImportDefaultChild", child)

    expect(child.attributes.key?(:def_imported)).to be(true)
    expect(parent.attributes.key?(:def_imported)).to be(false)
    expect(source.attributes.key?(:def_imported)).to be(true)
  end

  it "serializes a trio byte-identically to independently declared models" do
    child = Class.new(parent) do
      attribute :note, :string
      xml do
        map_element "note", to: :note
      end
    end
    stub_const("IsoTrioChild", child)
    sibling = Class.new(parent) do
      attribute :flag, :string
      xml do
        map_element "flag", to: :flag
      end
    end
    stub_const("IsoTrioSibling", sibling)

    inherited = child.from_xml("<parent name=\"n\"><size>1</size><note>x</note></parent>")
    standalone = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :size, :integer
      attribute :note, :string
      xml do
        element "parent"
        map_attribute "name", to: :name
        map_element "size", to: :size
        map_element "note", to: :note
      end
    end
    stub_const("IsoTrioStandalone", standalone)

    expect(inherited.to_xml).to include("<size>1</size>")
    expect(inherited.to_xml).to include("<note>x</note>")
    expect(standalone.from_xml(inherited.to_xml).to_xml).to eq(inherited.to_xml)
    expect(sibling.from_xml("<parent name=\"s\"><flag>1</flag></parent>").to_xml)
      .to include("<flag>1</flag>")
  end

  it "keeps grandparent chains isolated in both directions" do
    mid = Class.new(parent) do
      attribute :mid_attr, :string
    end
    stub_const("IsoMid", mid)
    leaf = Class.new(mid)
    stub_const("IsoLeaf", leaf)

    parent.attribute :gp_late, :string
    mid.attribute :mid_late, :string

    expect(leaf.attributes.key?(:name)).to be(true)
    expect(leaf.attributes.key?(:mid_attr)).to be(true)
    expect(leaf.attributes.key?(:gp_late)).to be(false)
    expect(leaf.attributes.key?(:mid_late)).to be(false)
    expect(mid.attributes.key?(:gp_late)).to be(false)
    expect(parent.attributes.key?(:mid_attr)).to be(false)
  end
end
