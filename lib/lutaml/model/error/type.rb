# frozen_string_literal: true

module Lutaml
  module Model
    module Error
      module Type
        autoload :InvalidValueError, "#{__dir__}/type/invalid_value_error"
        autoload :MinBoundError, "#{__dir__}/type/min_bound_error"
        autoload :MaxBoundError, "#{__dir__}/type/max_bound_error"
        autoload :PatternNotMatchedError, "#{__dir__}/type/pattern_not_matched_error"
        autoload :MinLengthError, "#{__dir__}/type/min_length_error"
        autoload :MaxLengthError, "#{__dir__}/type/max_length_error"
      end
    end
  end
end
