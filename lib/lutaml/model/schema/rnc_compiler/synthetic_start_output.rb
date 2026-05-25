# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RncCompiler
        # Removes the synthetic Start model produced when RNC `start |=`
        # appears as a define instead of an RNG start element.
        class SyntheticStartOutput
          def self.remove(output, grammar)
            return unless synthetic_start_define?(grammar)

            output.classes.delete("Start")
            output.sources.delete("Start")
          end

          def self.synthetic_start_define?(grammar)
            Array(grammar.start).empty? &&
              Array(grammar.define).any? { |define| define.name == "start" }
          end

          private_class_method :synthetic_start_define?
        end
      end
    end
  end
end
