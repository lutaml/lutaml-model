# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      autoload :Json, "#{__dir__}/adapter/json"
      autoload :Yaml, "#{__dir__}/adapter/yaml"
      autoload :Toml, "#{__dir__}/adapter/toml"
      autoload :Hash, "#{__dir__}/adapter/hash"
      autoload :Jsonl, "#{__dir__}/adapter/jsonl"
      autoload :Yamls, "#{__dir__}/adapter/yamls"
    end
  end
end
