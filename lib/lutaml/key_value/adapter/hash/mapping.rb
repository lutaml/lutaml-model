module Lutaml
  module KeyValue
    module Adapter
      module Hash
        class Mapping < Lutaml::KeyValue::Mapping
          def initialize
            super(:hash)
          end

          def deep_dup
            self.class.new.tap do |new_mapping|
              new_mapping.instance_variable_set(:@mappings, duplicate_mappings)
            end
          end
        end
      end
    end
  end
end
