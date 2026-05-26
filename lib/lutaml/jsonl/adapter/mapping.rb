# frozen_string_literal: true

module Lutaml
  module Jsonl
    module Adapter
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
