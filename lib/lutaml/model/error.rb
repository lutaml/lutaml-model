module Lutaml
  module Model
    class Error < StandardError
      def flatten_nested_attributes(array, object_class)
        array.flat_map do |attr|
          attr.is_a?(object_class) ? attr.attributes.map(&:name) : attr
        end
      end
    end
  end
end

require_relative "error/invalid_value_error"
require_relative "error/incorrect_mapping_argument_error"
require_relative "error/pattern_not_matched_error"
require_relative "error/unknown_adapter_type_error"
require_relative "error/collection_count_out_of_range_error"
require_relative "error/validation_error"
require_relative "error/type_not_enabled_error"
require_relative "error/type_error"
require_relative "error/unknown_type_error"
require_relative "error/multiple_mappings_error"
require_relative "error/collection_true_missing_error"
require_relative "error/type/invalid_value_error"
require_relative "error/incorrect_sequence_error"
require_relative "error/choice_upper_bound_error"
require_relative "error/no_root_mapping_error"
require_relative "error/import_model_with_root_error"
require_relative "error/invalid_choice_range_error"
require_relative "error/unknown_sequence_mapping_error"
require_relative "error/choice_lower_bound_error"
require_relative "error/no_root_namespace_error"
