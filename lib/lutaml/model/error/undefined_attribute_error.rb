module Lutaml
  module Model
    class UndefinedAttributeError < Error
      def initialize(attr_name, klass)
        super("#{attr_name} is not defined in #{klass}")
      end
    end
  end
end
