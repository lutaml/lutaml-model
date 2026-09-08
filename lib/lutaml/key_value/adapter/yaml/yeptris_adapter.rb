# frozen_string_literal: true

require_relative "../../../yaml/adapter/yeptris_adapter"

module Lutaml
  module KeyValue
    module Adapter
      module Yaml
        # Backward-compatibility entry for the adapter resolver's default
        # load path; the implementation lives in Lutaml::Yaml::Adapter.
        YeptrisAdapter = Lutaml::Yaml::Adapter::YeptrisAdapter
      end
    end
  end
end
