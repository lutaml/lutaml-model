# frozen_string_literal: true

module Lutaml
  module Yamls
    module Adapter
      class Mapping < Lutaml::KeyValue::Mapping
        attr_accessor :yamls_sequence

        def initialize
          super(:yaml)
        end

        def sequence(&)
          @yamls_sequence = YamlsSequence.new
          @yamls_sequence.instance_eval(&)
        end

        def dup_instance
          self.class.new
        end

        def deep_dup
          super.tap do |new_mapping|
            new_mapping.yamls_sequence = @yamls_sequence&.dup
          end
        end
      end
    end
  end
end
