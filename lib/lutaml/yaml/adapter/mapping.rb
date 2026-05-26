# frozen_string_literal: true

module Lutaml
  module Yaml
    module Adapter
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
