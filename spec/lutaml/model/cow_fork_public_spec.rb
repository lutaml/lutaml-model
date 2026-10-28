# frozen_string_literal: true

require "spec_helper"

# Copy-on-write inheritance shares a subclass's structures with its
# superclass until the class's own DSL forks them. External mutators — a
# library pruning an inherited attribute on one subclass (relaton's
# Item-header prunes) — need a supported way to claim ownership first, or
# the mutation erases the attribute for every sibling class.
RSpec.describe "Lutaml::Model::Serializable#lutaml_cow_fork!" do
  let(:parent_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :shared, :string

      xml do
        root "parent"
        map_attribute "id", to: :id
        map_element "shared", to: :shared
      end
    end
  end

  let(:child_class) do
    Class.new(parent_class)
  end

  it "is callable from outside the DSL" do
    expect(child_class).to respond_to(:lutaml_cow_fork!)
  end

  it "gives the class a private copy without touching the superclass" do
    parent_attributes = parent_class.class_attributes
    child_class.lutaml_cow_fork!(:attributes)

    expect(child_class.class_attributes).not_to equal(parent_attributes)
    expect(parent_class.class_attributes).to equal(parent_attributes)
  end

  it "keeps post-fork mutations private to the forking class" do
    child_class.lutaml_cow_fork!(:attributes)
    child_class.lutaml_cow_fork!(:mappings)
    child_class.class_attributes.delete(:id)
    child_class.mappings[:xml]
               .instance_variable_get(:@attributes)
               .delete("id")

    expect(parent_class.class_attributes).to be_key(:id)
    expect(parent_class.mappings[:xml]
      .instance_variable_get(:@attributes)).to be_key("id")
    expect(child_class.class_attributes).not_to be_key(:id)
  end

  it "does not fork an already-owned structure into a new object" do
    child_class.lutaml_cow_fork!(:attributes)
    owned = child_class.class_attributes
    child_class.lutaml_cow_fork!(:attributes)

    expect(child_class.class_attributes).to equal(owned)
  end
end
