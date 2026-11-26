# frozen_string_literal: true

module Lutaml
  module Lml
    # A derived-field declaration: existence + type only. The
    # computation is bound by the binder from the grammar artifact's
    # derive specs — LML never defines computation.
    #   derive urn: String
    class DerivedField < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :type, :string
    end
  end
end
