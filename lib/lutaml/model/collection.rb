module Lutaml
  module Model
    class Collection < Array
      # Overriding map method to return Collection instead of Array
      def map(&block)
        self.class.new(super)
      end

      # Overriding push method to return Collection instead of Array
      def push(*args)
        super # Use Array's original push method
        self # Return the Collection instance
      end

      # Overriding compact method to return Collection instead of Array
      def compact
        self.class.new(super) # Use Array's original compact and wrap in Collection
      end

      # Overriding flatten method to return Collection instead of Array
      def flatten(level = nil)
        self.class.new(super) # Use Array's original flatten and wrap in Collection
      end
    end
  end
end
