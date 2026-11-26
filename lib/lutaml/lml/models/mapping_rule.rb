# frozen_string_literal: true

module Lutaml
  module Lml
    # One line of a serialization mapping: what kind of mapping (element,
    # attribute, content, map, key, value), the serialization-side wire
    # name, the model attribute it binds, and the qualifier mode for
    # key/value collections (to_instance, as_attribute).
    class MappingRule < Lutaml::Model::Serializable
      attribute :kind, :string
      attribute :wire, :string
      attribute :field, :string
      attribute :mode, :string
    end
  end
end
