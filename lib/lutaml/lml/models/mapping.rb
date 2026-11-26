# frozen_string_literal: true

module Lutaml
  module Lml
    # A lutaml-model wire-name mapping declared inside an LML class:
    #   mapping yaml { map "full-name", to: "name" }
    # One entry per map line; `format` is the target serialization
    # (yaml, xml, json, toml, csv).
    class Mapping < Lutaml::Model::Serializable
      attribute :format, :string
      attribute :wire, :string
      attribute :to, :string
    end
  end
end
