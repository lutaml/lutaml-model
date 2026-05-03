# frozen_string_literal: true

module Lutaml
  module Yamls
    module Adapter
      class Mapping < Lutaml::KeyValue::Mapping
        attr_reader :yamls_sequence

        def initialize
          super(:yaml)
        end

        def sequence(&)
          @yamls_sequence = YamlsSequence.new
          @yamls_sequence.instance_eval(&)
        end

        def deep_dup
          self.class.new.tap do |new_mapping|
            new_mapping.mappings = duplicate_mappings
          end
        end
      end
    end
  end
end
