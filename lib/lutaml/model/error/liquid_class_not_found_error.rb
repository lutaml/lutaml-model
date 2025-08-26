module Lutaml
  module Model
    class LiquidClassNotFoundError < Error
      def initialize(class_name)
        super("Liquid class '#{class_name}' is not defined in memory. Please ensure the class is loaded before using it.")
      end
    end
  end
end
