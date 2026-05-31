module Lutaml
  module Model
    class TypeOnlyMappingError < Error
      def initialize(model)
        super("#{model} is a type-only model (no element declared), " \
              "it can only be used as an embedded type through a parent model.")
      end
    end

    # @deprecated Use {TypeOnlyMappingError} instead.
    NoRootMappingError = TypeOnlyMappingError
  end
end
