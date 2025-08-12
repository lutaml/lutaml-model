module Lutaml
  module Model
    class NoMappingFoundError < Error
      def initialize(type_name)
        super("No mapping available for `#{type_name}`")
      end
    end
  end
end
