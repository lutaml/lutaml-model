# frozen_string_literal: true

require "moxml"
if RUBY_ENGINE == 'opal'
  require 'corelib/array/pack'
  require 'corelib/trace_point'
  require 'moxml'
  require 'lutaml/model/xml/oga_adapter'
  require 'lutaml/model/schema/xml_compiler'
end
require_relative "model/uninitialized_class"
require_relative "model/errors"
require_relative "model/services"
require_relative "model/version"
require_relative "model/type"
require_relative "model/utils"
require_relative "model/serializable"
require_relative "model/xml_adapter"
require_relative "model/error"
require_relative "model/constants"
require_relative "model/config"
require_relative "model/global_register"
require_relative "model/register"
require_relative "model/format_registry"
require_relative "model/collection"
require_relative "model/key_value_document"
require_relative "model/yaml"
require_relative "model/yamls"
require_relative "model/json"
require_relative "model/jsonl"
require_relative "model/toml"
require_relative "model/hash"
require_relative "model/xml"

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
