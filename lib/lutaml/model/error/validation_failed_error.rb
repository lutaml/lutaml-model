module Lutaml
  module Model
    class ValidationFailedError < Error
      def initialize(errors)
        super("Validation failed: #{errors.map { |e| "`#{e}`" }.join(', ')}")
      end
    end
  end
end
