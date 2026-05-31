# frozen_string_literal: true

require_relative "type_only_mapping_error"

module Lutaml
  module Model
    # @deprecated Use {TypeOnlyMappingError} instead.
    NoRootMappingError = TypeOnlyMappingError
  end
end
