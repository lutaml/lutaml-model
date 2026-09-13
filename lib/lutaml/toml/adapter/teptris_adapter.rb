# frozen_string_literal: true

require_relative "../../key_value/adapter/toml/teptris_adapter"

module Lutaml
  module Toml
    module Adapter
      # The implementation lives in the KeyValue namespace (the live
      # surface for adapter resolution); this alias keeps the legacy
      # Lutaml::Toml::Adapter surface complete.
      TeptrisAdapter = Lutaml::KeyValue::Adapter::Toml::TeptrisAdapter
    end
  end
end
