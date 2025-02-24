module Lutaml
  module Model
    class IncorrectMappingArgumentsError < Error
      def self.invalid_with_values(missing_method_keys, name)
        val = "value".pluralize(missing_method_keys.count)
        key = "key".pluralize(missing_method_keys.count)

        new("Missing #{val} for `with` #{key} `#{missing_method_keys.join(', ')}` in mapping `#{name}`")
      end

      def self.missing_mapping_arguments(with, name)
        message = if with.one?
                    "to: <attribute_name> is required for mapping '#{name}'"
                  else
                    ":to or :with argument is required for mapping '#{name}'"
                  end

        new(message)
      end
    end
  end
end
