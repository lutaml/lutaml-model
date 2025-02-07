module Lutaml
  module Model
    class ImportModelWithRootError < Error
      def initialize(model)
        super("Cannot import a model `#{model}` with a root element")
      end
    end
  end
end
