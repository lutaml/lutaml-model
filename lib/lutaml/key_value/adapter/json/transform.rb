# frozen_string_literal: true

# Backward compatibility - delegates to Lutaml::Json::Adapter
# @deprecated Use Lutaml::Json::Adapter::Transform instead

module Lutaml
  module KeyValue
    module Adapter
      module Json
        class Transform < Lutaml::KeyValue::Transform; end
      end
    end
  end
end
