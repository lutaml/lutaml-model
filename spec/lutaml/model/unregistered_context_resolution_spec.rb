# frozen_string_literal: true

require "spec_helper"

# Register ids and type-context ids are two namespaces that
# GlobalContext#resolve_type bridges implicitly: an id present only in the
# Register namespace (a flavor's `lutaml_default_register`) resolves to a
# nil type context, and every resolution shape must treat that as a
# legitimate "no namespace" input instead of crashing (metanorma-jis#531).
RSpec.describe "type resolution through a register id with no registered type context" do
  let(:collection_class) do
    Class.new(Lutaml::Model::Collection) do
      instances :entries, :string
    end
  end

  it "resolves collection instance types under a nil context" do
    collection = collection_class.new(["a"], lutaml_register: :jis_document)

    expect(collection.entries).to eq(["a"])
  end

  it "resolves built-in symbol names under a nil context" do
    resolved = Lutaml::Model::GlobalContext.resolve_type(:string, :jis_document)

    expect(resolved).to eq(Lutaml::Model::Type::String)
  end

  it "raises UnknownTypeError for unknown names under a nil context" do
    expect do
      Lutaml::Model::GlobalContext.resolve_type(:no_such_type, :jis_document)
    end.to raise_error(Lutaml::Model::UnknownTypeError)
  end
end
