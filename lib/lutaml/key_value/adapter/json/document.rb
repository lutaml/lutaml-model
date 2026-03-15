# frozen_string_literal: true

# Backward compatibility - delegates to Lutaml::Json::Adapter
# @deprecated Use Lutaml::Json::Adapter::Document instead

module Lutaml
  module KeyValue
    module Adapter
      module Json
        # Base class for JSON documents
        class Document < Lutaml::KeyValue::Document
        end
      end
    end
  end
end
