# frozen_string_literal: true

# Backwards compatibility alias
# YamlSchema has moved to Lutaml::Yaml::Schema::YamlSchema
#
# @deprecated Use Lutaml::Yaml::Schema::YamlSchema instead

require_relative "../../yaml/schema/yaml_schema"

module Lutaml
  module Model
    module Schema
      # For backwards compatibility, delegate to the new location
      YamlSchema = ::Lutaml::Yaml::Schema::YamlSchema
    end
  end
end
