
module Lutaml
  module Model
    class Mapping
      def mappings
        raise NotImplementedError, "#{self.class.name} must implement `mappings`."
      end
    end
  end
end

require_relative "mapping/key_value_mapping"
require_relative "mapping/key_value_mapping_rule"
require_relative "mapping/mapping_rule"
require_relative "mapping/xml_mapping"
require_relative "mapping/xml_mapping_rule"
