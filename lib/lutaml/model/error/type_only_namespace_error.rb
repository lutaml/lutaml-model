module Lutaml
  module Model
    class TypeOnlyNamespaceError < Error
      def to_s
        "Cannot assign namespace to a type-only model (no element declared)."
      end
    end

    # @deprecated Use {TypeOnlyNamespaceError} instead.
    NoRootNamespaceError = TypeOnlyNamespaceError
  end
end
