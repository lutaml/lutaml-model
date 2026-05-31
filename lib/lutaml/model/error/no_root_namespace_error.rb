# frozen_string_literal: true

require_relative "type_only_namespace_error"

module Lutaml
  module Model
    # @deprecated Use {TypeOnlyNamespaceError} instead.
    NoRootNamespaceError = TypeOnlyNamespaceError
  end
end
