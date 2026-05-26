module Lutaml
  module KeyValue
    module Adapter
      module Hash
        class Mapping < Lutaml::KeyValue::Mapping
          def initialize
            super(:hash)
          end

          def dup_instance
            self.class.new
          end
        end
      end
    end
  end
end
