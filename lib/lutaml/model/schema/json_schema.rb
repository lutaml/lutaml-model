# frozen_string_literal: true

# Backwards compatibility alias
# JsonSchema has moved to Lutaml::Json::Schema::JsonSchema
#
# @deprecated Use Lutaml::Json::Schema::JsonSchema instead

require_relative "../../json/schema/json_schema"

module Lutaml
  module Model
    module Schema
      # For backwards compatibility, delegate to the new location
      JsonSchema = ::Lutaml::Json::Schema::JsonSchema
    end
  end
end
