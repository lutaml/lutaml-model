# frozen_string_literal: true

require_relative "model/version"

# lib/lutaml/model.rb
require "nokogiri"
require "json"
require "yaml"
require_relative "model/type"
require_relative "model/serializable"
require_relative "model/serializers/json_serializer"
require_relative "model/serializers/yaml_serializer"
require_relative "model/serializers/xml_serializer"

module Lutaml
  module Model
    class BaseModel < Serializable
    end
  end
end
