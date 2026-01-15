# frozen_string_literal: true

require_relative "key_value_data_model/key_value_element"

module Lutaml
  module Model
    # Pure data classes for key-value intermediate representation.
    #
    # These classes represent key-value structures (JSON, YAML, TOML) without
    # serialization logic, allowing transformation to produce key-value data
    # that can be serialized by different adapters.
    #
    # This provides the same architectural symmetry for key-value formats
    # that XmlDataModel provides for XML.
    module KeyValueDataModel
      # Base module for key-value data model classes
    end
  end
end