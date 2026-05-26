module Lutaml
  module KeyValue
    module Adapter
      module Jsonl
        class Mapping < Lutaml::KeyValue::Mapping
          def initialize
            super(:jsonl)
          end

          def dup_instance
            self.class.new
          end
        end
      end
    end
  end
end
