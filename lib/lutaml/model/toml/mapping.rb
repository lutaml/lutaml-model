require_relative "../mapping/key_value_mapping"

module Lutaml
  module Model
    module Toml
      class Mapping < Lutaml::Model::KeyValueMapping
        def initialize
          super(:toml)
        end

        def deep_dup
          self.class.new.tap do |new_mapping|
            new_mapping.instance_variable_set(:@mappings, duplicate_mappings)
          end
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
end
