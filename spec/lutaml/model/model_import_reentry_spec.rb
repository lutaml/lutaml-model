# frozen_string_literal: true

require "spec_helper"

# Issue #938: a deferred (symbol-form) import that cannot resolve leaves
# the import pass with all_resolved = false. record_import_attempt then
# calls attributes(), which re-enters ensure_imports!; the completion
# marker stored false before that call, so the re-entrant pass ran the
# import loop again and recursed to SystemStackError. Consumers with
# large mutually-referencing type graphs (uniword OOXML sets) hit this
# on load.
RSpec.describe "deferred model import re-entry" do
  class Reentry938OrphanSource < Lutaml::Model::Serializable
    attribute :label, :string
  end

  class Reentry938PendingImporter < Lutaml::Model::Serializable
    attribute :name, :string
    import_model_attributes :NoSuchModelAnywhere938
  end

  class Reentry938ResolvableImporter < Lutaml::Model::Serializable
    attribute :name, :string
    import_model_attributes :Reentry938OrphanSource
  end

  it "does not recurse when a deferred import cannot resolve" do
    expect { Reentry938PendingImporter.attributes(:default) }
      .not_to raise_error
  end

  it "resolves a deferred import without recursing on re-access" do
    Lutaml::Model::GlobalRegister
      .lookup(Lutaml::Model::Config.default_register)
      .register_model(Reentry938OrphanSource, id: :Reentry938OrphanSource)
    importer = Reentry938ResolvableImporter

    3.times { importer.attributes(:default) }

    expect(importer.attributes(:default)).to have_key(:name)
    expect(importer.attributes(:default)).to have_key(:label)
  end
end
