module Lutaml
  module Model
    class RequiredAttributeMissingError < Error
      def initialize(attribute)
        super("Missing required attribute: #{attribute}")
      end
    end
  end
end
