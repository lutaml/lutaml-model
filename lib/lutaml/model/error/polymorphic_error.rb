module Lutaml
  module Model
    class PolymorphicError < Error
      def initialize(value, options, type)
        error = if options[:polymorphic].is_a?(Array)
                  "#{value.class} not in #{options[:polymorphic]}"
                else
                  "#{value.class} is not valid sub class of #{type}"
                end
        super(error)
      end
    end
  end
end
