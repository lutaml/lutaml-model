require "spec_helper"
require_relative "../../../lib/lutaml/model"

module UnregisteredContextSpec
  class Item < Lutaml::Model::Serializable
    attribute :name, :string
    xml do
      root "item"
      map_element "name", to: :name
    end
  end

  class Doc < Lutaml::Model::Serializable
    attribute :items, Item, collection: true
    xml do
      root "doc"
      map_element "item", to: :items
    end
  end
end

RSpec.describe "type resolution through a context id with no registered type context" do
  # A register id (the Register namespace) is not a type-context id (the
  # TypeContext namespace); resolving a class-typed collection through it
  # must not crash the cache key on a nil context.
  it "resolves collections when the context id resolves to nil" do
    allow(Lutaml::Model::Config).to receive(:default_register).and_return(:no_such_context)

    doc = UnregisteredContextSpec::Doc.from_xml(
      "<doc><item><name>a</name></item></doc>",
    )

    expect(doc.items.map(&:name)).to eq(["a"])
  end

  it "caches class-typed resolutions under a nil context without error" do
    resolver = Lutaml::Model::CachedTypeResolver.allocate
    key = resolver.send(:context_id_for, nil)
    expect(key).to be_nil
  end
end
