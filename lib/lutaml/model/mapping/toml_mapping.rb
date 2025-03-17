require_relative "key_value_mapping"

module Lutaml
  module Model
    class TomlMapping < KeyValueMapping
      def initialize
        super(:toml)
      end

      def validate!(key, to, with, render_nil, render_empty)
        super

        if [true, :nil].include?(render_nil) || render_empty == :nil
          raise ArgumentError, "nil values are not supported in toml format"
        end
      end
    end
  end
end
