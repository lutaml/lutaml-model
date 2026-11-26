# frozen_string_literal: true

module Lutaml
  module Lml
    # A grammar-backed string format declared on a class (or as a
    # models-block default): a thin reference — the artifact owns the
    # capture maps and render specs; LML only names format, artifact,
    # and entry root.
    #   string_format :pubid { artifact "pubid/iso"  root "iso_identifier" }
    class StringFormat < Lutaml::Model::Serializable
      attribute :format, :string
      attribute :artifact, :string
      attribute :root, :string
    end
  end
end
