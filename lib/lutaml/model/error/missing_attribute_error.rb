module Lutaml
  module Model
    class MissingAttributeError < Error
      def initialize(attribute)
        super("Missing required attribute: #{attribute}")
      end
    end
  end
end
