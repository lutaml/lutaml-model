# frozen_string_literal: true

# Backward compatibility - delegates to Lutaml::Json::Adapter
# @deprecated Use Lutaml::Json::Adapter::Mapping instead

module Lutaml
  module KeyValue
    module Adapter
      module Json
        class Mapping < Lutaml::KeyValue::Mapping
          def initialize
            super(:json)
          end

          def dup_instance
            self.class.new
          end
        end
      end
    end
  end
end
