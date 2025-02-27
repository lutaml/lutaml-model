module Lutaml
  module Model
    class PolymorphicError < Error
      def initialize(value, options)
        super("#{value.class} not in #{options[:polymorphic]}")
      end
    end
  end
end
