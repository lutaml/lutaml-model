module Lutaml
  module Model
    class UnknownSequenceMappingError < Error
      def initialize(method_name)
        super("#{method_name} is not allowed in sequence")
      end
    end
  end
end
