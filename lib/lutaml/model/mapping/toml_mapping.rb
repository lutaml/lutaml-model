require_relative "key_value_mapping"

module Lutaml
  module Model
    class TomlMapping < KeyValueMapping
      def initialize
        super(:toml)
      end

      def validate!(key, to, with, render_nil, render_empty)
        super

        if [true, :as_nil].include?(render_nil) || render_empty == :as_nil
          raise IncorrectMappingArgumentsError, "nil values are not supported in toml format"
        end
      end
    end
  end
end
