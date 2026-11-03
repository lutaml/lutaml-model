# frozen_string_literal: true

require_relative "../../../yamls/adapter/yeptris_adapter"

module Lutaml
  module KeyValue
    module Adapter
      module Yamls
        # Backward-compatibility entry for the adapter resolver's default
        # load path; the implementation lives in Lutaml::Yamls::Adapter.
        YeptrisAdapter = Lutaml::Yamls::Adapter::YeptrisAdapter
      end
    end
  end
end
