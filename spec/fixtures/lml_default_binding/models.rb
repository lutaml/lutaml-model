# frozen_string_literal: true

require "lutaml/model"

# Models with Proc defaults for lml_default_binding_spec. executed records
# every time a default body runs: export must leave it empty.
module LmlDefaultBindingFixtures
  def self.executed
    @executed ||= []
  end

  def self.record(key, value)
    executed << key
    value
  end

  class CodeType < Lutaml::Model::Type::String; end

  class Subject < Lutaml::Model::Serializable
    attribute :lang, :string, default: -> { LmlDefaultBindingFixtures.record(:lang, "never") }
    attribute :flag, :boolean, default: -> { LmlDefaultBindingFixtures.record(:flag, true) }
    attribute :note, :string, default: -> { LmlDefaultBindingFixtures.record(:note, "x") }
    attribute :tags, :string, collection: true, default: -> { LmlDefaultBindingFixtures.record(:tags, []) }
    attribute :ratio, :float, default: -> { LmlDefaultBindingFixtures.record(:ratio, 0.5) }
    attribute :code, CodeType, default: -> { LmlDefaultBindingFixtures.record(:code, "zz") }
    attribute :fixed, :string, default: "kept"
    attribute :bare, :string

    json do
      map "lang", to: :lang
      map "flag", to: :flag
      map "note", to: :note
      map "tags", to: :tags
      map "ratio", to: :ratio
      map "code", to: :code
      map "fixed", to: :fixed
      map "bare", to: :bare
    end
  end

  class Parent < Lutaml::Model::Serializable
    attribute :subject, Subject

    json do
      map "subject", to: :subject
    end
  end
end
