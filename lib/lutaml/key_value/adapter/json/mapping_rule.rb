# frozen_string_literal: true

# Backward compatibility - delegates to Lutaml::Json::Adapter
# @deprecated Use Lutaml::Json::Adapter::MappingRule instead

module Lutaml
  module KeyValue
    module Adapter
      module Json
        class MappingRule < Lutaml::KeyValue::MappingRule; end
      end
    end
  end
end
