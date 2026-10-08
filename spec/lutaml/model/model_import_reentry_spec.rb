# frozen_string_literal: true

require "spec_helper"

# Issue #938: a deferred (symbol-form) import that cannot resolve leaves
# the import pass with all_resolved = false. record_import_attempt then
# calls attributes(), which re-enters ensure_imports!; the completion
# marker stored false before that call, so the re-entrant pass ran the
# import loop again and recursed to SystemStackError. Consumers with
# large mutually-referencing type graphs (uniword OOXML sets) hit this
# on load.
module ModelImportReentry938
  class OrphanSource < Lutaml::Model::Serializable
    attribute :label, :string
  end

  class PendingImporter < Lutaml::Model::Serializable
    attribute :name, :string
    import_model_attributes :NoSuchModelAnywhere938
  end

  class ResolvableImporter < Lutaml::Model::Serializable
    attribute :name, :string
  end

  Lutaml::Model::GlobalRegister
    .lookup(Lutaml::Model::Config.default_register)
    .register_model(OrphanSource, id: :ModelImportReentry938OrphanSource)
  ResolvableImporter
    .import_model_attributes(:ModelImportReentry938OrphanSource)
end

RSpec.describe "deferred model import re-entry" do
  it "does not recurse when a deferred import cannot resolve" do
    expect { ModelImportReentry938::PendingImporter.attributes(:default) }
      .not_to raise_error
  end

  it "resolves a deferred import without recursing on re-access" do
    importer = ModelImportReentry938::ResolvableImporter
    3.times { importer.attributes(:default) }

    expect(importer.attributes(:default)).to have_key(:name)
    expect(importer.attributes(:default)).to have_key(:label)
  end
end
