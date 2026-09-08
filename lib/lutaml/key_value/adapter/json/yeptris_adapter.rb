# frozen_string_literal: true

require_relative "../../../json/adapter/yeptris_adapter"

module Lutaml
  module KeyValue
    module Adapter
      module Json
        # Backward-compatibility entry for the adapter resolver's default
        # load path; the implementation lives in Lutaml::Json::Adapter.
        YeptrisAdapter = Lutaml::Json::Adapter::YeptrisAdapter
      end
    end
  end
end
