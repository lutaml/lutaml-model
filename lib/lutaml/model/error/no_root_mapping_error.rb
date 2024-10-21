module Lutaml
  module Model
    class NoRootMappingError < Error
      def initialize(model)
        super("#{model} has `no_root`, it allowed only for reusable models")
      end
    end
  end
end
