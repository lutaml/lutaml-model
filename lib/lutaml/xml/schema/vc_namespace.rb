# frozen_string_literal: true

require_relative "../namespace"

module Lutaml
  module Xml
    module Schema
      # W3C XML Schema Versioning Namespace (XSD 1.1 §C.1)
      #
      # The vc: namespace carries the schema-dialect markers
      # (vc:minVersion / vc:maxVersion / vc:typeAvailable ...) that
      # gate 1.1-only constructs on 1.0-labeled schemas. The engine
      # tier compiles alternatives, openContent and assertions only
      # when the marker survives to compilation — the roundtrip must
      # not erase it (#1222).
      #
      # @see https://www.w3.org/2007/XMLSchema-versioning
      class VcNamespace < Lutaml::Xml::Namespace
        uri "http://www.w3.org/2007/XMLSchema-versioning"
        prefix_default "vc"
      end
    end
  end
end
