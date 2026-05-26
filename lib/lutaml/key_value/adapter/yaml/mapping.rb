module Lutaml
  module KeyValue
    module Adapter
      module Yaml
        class Mapping < Lutaml::KeyValue::Mapping
          def initialize
            super(:yaml)
          end

          def dup_instance
            self.class.new
          end
        end
      end
    end
  end
end
