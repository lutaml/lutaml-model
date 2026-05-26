# frozen_string_literal: true

module Lutaml
  module HashFormat
    module Adapter
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
