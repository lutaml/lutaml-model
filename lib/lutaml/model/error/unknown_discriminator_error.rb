# frozen_string_literal: true

module Lutaml
  module Model
    # Raised when a `when_attribute` rule declared `unmatched: :raise`
    # parses an occurrence that no rule claims: it matches no
    # discriminator and no plain rule shares the wire name.
    class UnknownDiscriminatorError < Error
    end
  end
end
