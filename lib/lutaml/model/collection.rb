module Lutaml
  module Model
    class Collection < Array
      # Overriding map method to return Collection instead of Array
      def map(&block)
        self.class.new(super)
      end

      # Overriding push method to return Collection instead of Array
      def push(*args)
        super
        self
      end

      # Overriding compact method to return Collection instead of Array
      def compact
        self.class.new(super)
      end

      # Overriding flatten method to return Collection instead of Array
      def flatten(level = nil)
        self.class.new(super)
      end
    end
  end
end
