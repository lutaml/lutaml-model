# frozen_string_literal: true

require_relative "model/version"

# lib/lutaml/model.rb
require "nokogiri"
require "json"
require "yaml"
require_relative "model/type"
require_relative "model/serializable"
require_relative "model/json_adapter"
require_relative "model/yaml_adapter"
require_relative "model/xml_adapter"
require_relative "model/toml_adapter"
require_relative "model/error"

module Lutaml
  module Model
    # Error for passing incorrect model type
    #
    # @api private
    class IncorrectModelError < StandardError
    end

    class BaseModel < Serializable
    end
  end
end
