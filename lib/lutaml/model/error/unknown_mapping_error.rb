# frozen_string_literal: true

module Lutaml
  module Model
    # Raised when a `mapping:` selection names a serialization mapping
    # profile the model does not declare (#176).
    class UnknownMappingError < Error
      def initialize(name, format)
        super(
          "unknown #{format} mapping profile #{name.inspect} — declare it " \
          "with `#{format} :#{name} do ... end` or wire it with " \
          "mapping :#{name}, mapping",
        )
      end
    end
  end
end
