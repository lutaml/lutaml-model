module Lutaml
  module Model
    module Mapping
    end
  end
end

require_relative "mapping/mapping_rule"
# require_relative "mapping/key_value_mapping"
require_relative "mapping/yaml_mapping"
require_relative "mapping/json_mapping"
require_relative "mapping/toml_mapping"
require_relative "mapping/key_value_mapping_rule"
require_relative "mapping/xml_mapping"
require_relative "mapping/xml_mapping_rule"
