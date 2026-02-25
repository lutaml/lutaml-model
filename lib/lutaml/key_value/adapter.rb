# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      autoload :Json, "lutaml/key_value/adapter/json"
      autoload :Yaml, "lutaml/key_value/adapter/yaml"
      autoload :Toml, "lutaml/key_value/adapter/toml"
      autoload :HashAdapter, "lutaml/key_value/adapter/hash"
      autoload :Jsonl, "lutaml/key_value/adapter/jsonl"
      autoload :Yamls, "lutaml/key_value/adapter/yamls"
    end
  end
end
