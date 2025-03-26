module Lutaml
  module Model
    class Mapping
      def initialize
        @mappings = []
      end

      def mappings
        raise NotImplementedError, "#{self.class.name} must implement `mappings`."
      end
    end
  end
end
