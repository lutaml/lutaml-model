module Lutaml
  module Model
    class Error < StandardError
    end
  end
end

require_relative "error/invalid_value_error"
require_relative "error/liquid_not_enabled_error"
require_relative "error/incorrect_mapping_argument_error"
require_relative "error/pattern_not_matched_error"
require_relative "error/unknown_adapter_type_error"
require_relative "error/collection_count_out_of_range_error"
require_relative "error/element_count_out_of_range_error"
require_relative "error/validation_error"
require_relative "error/type_not_enabled_error"
require_relative "error/type_error"
require_relative "error/unknown_type_error"
require_relative "error/multiple_mappings_error"
require_relative "error/collection_true_missing_error"
require_relative "error/type/invalid_value_error"
require_relative "error/type/min_bound_error"
require_relative "error/type/max_bound_error"
require_relative "error/type/pattern_not_matched_error"
require_relative "error/type/min_length_error"
require_relative "error/type/max_length_error"
require_relative "error/incorrect_sequence_error"
require_relative "error/choice_upper_bound_error"
require_relative "error/no_root_mapping_error"
require_relative "error/import_model_with_root_error"
require_relative "error/invalid_choice_range_error"
require_relative "error/unknown_sequence_mapping_error"
require_relative "error/choice_lower_bound_error"
require_relative "error/no_root_namespace_error"
require_relative "error/polymorphic_error"
require_relative "error/validation_failed_error"
require_relative "error/invalid_attribute_name_error"
require_relative "error/invalid_attribute_options_error"
require_relative "error/register/not_registrable_class_error"
