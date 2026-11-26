# frozen_string_literal: true

require "lutaml/model"

module Lutaml
  module Lml
    # The type of an LML attribute literal: a scalar, a list, or a map.
    #
    # This exists as a subclass rather than using Lutaml::Model::Type::Value
    # directly because lutaml-model's key-value serializer tests the declared
    # attribute type with a strict `attribute_type < Type::Value`. Type::Value
    # is not a strict subclass of itself, so declaring it hands the serializer
    # the raw wrapper object: JSON calls to_json(state) on it and raises
    # ArgumentError, and Psych emits a !ruby/object tag that from_yaml then
    # refuses to load. A subclass puts the attribute on the working path, where
    # the serializer asks the wrapper for its value instead.
    #
    # Deleting this class needs two upstream changes, not one: that `<` widened
    # to `<=`, and the serializer no longer re-wrapping a value it already
    # wrapped. Widening `<` alone still leaves the nested wrapper below.
    class LiteralValue < Lutaml::Model::Type::Value
      # The serializer re-wraps an already-wrapped value before asking it for a
      # format, so #value has to see through that extra layer. Every to_<format>
      # method lutaml-model generates reads through here, which is why this is
      # one override rather than one per format.
      def value
        wrapped = super
        wrapped.is_a?(LiteralValue) ? wrapped.value : wrapped
      end
    end
  end
end
