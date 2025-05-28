module Lutaml
  module Model
    class InvalidAttributeOptionsError < Error
      def initialize(name, invalid_opts)
        @name = name
        @invalid_opts = invalid_opts

        super()
      end

      def to_s
        "Invalid options given for `#{@name}` #{@invalid_opts}"
      end
    end
  end
end
