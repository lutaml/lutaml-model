# frozen_string_literal: true

module Lutaml
  module Json
    module Adapter
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
