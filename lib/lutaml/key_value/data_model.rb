# frozen_string_literal: true

module Lutaml
  module KeyValue
    # Pure data classes for key-value intermediate representation.
    #
    # These classes represent key-value structures (JSON, YAML, TOML) without
    # serialization logic, allowing transformation to produce key-value data
    # that can be serialized by different adapters.
    module DataModel
      autoload :Element, "#{__dir__}/data_model/element"
    end
  end
end
