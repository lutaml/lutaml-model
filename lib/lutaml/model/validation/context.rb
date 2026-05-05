# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      class Context
        attr_reader :errors

        def initialize
          @errors = []
          @per_rule_state = {}
        end

        def add_error(issue)
          @errors << issue
        end

        def add_errors(issues)
          @errors.concat(issues)
        end

        def rule_state(rule_code)
          @per_rule_state[rule_code] ||= {}
        end

        def reset!
          @errors.clear
          @per_rule_state.clear
        end
      end
    end
  end
end
