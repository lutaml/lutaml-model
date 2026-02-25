module Lutaml
  module KeyValue
    module Adapter
      module Json
        class Mapping < Lutaml::KeyValue::Mapping
          def initialize
            super(:json)
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
