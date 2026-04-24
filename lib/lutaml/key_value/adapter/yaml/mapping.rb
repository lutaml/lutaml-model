module Lutaml
  module KeyValue
    module Adapter
      module Yaml
        class Mapping < Lutaml::KeyValue::Mapping
          def initialize
            super(:yaml)
          end

          def deep_dup
            self.class.new.tap do |new_mapping|
              new_mapping.mappings = duplicate_mappings
            end
          end
        end
      end
    end
  end
end
