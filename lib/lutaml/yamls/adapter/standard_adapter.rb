# frozen_string_literal: true

require_relative "../../key_value/adapter/yamls/standard_adapter"

module Lutaml
  module Yamls
    module Adapter
      # Backward-compatibility entry; the implementation lives in
      # Lutaml::KeyValue::Adapter::Yamls so the adapter resolver's
      # generic class resolution lands on the production semantics.
      StandardAdapter = Lutaml::KeyValue::Adapter::Yamls::StandardAdapter
    end
  end
end
