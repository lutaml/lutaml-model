# frozen_string_literal: true

require_relative "../namespace"

module Lutaml
  module Xml
    module Schema
      # W3C XML Schema Versioning (VC) Namespace
      #
      # Carries the XSD 1.1 schema-versioning annotations
      # (vc:minVersion / vc:maxVersion and the conditional-type family,
      # XSD 1.1 §C.1). Components marked with these attributes only
      # apply when the validating processor speaks the marked dialect —
      # the engine tier gates its 1.1 compilation on vc:minVersion.
      #
      # @see https://www.w3.org/2007/XMLSchema-versioning
      class VcNamespace < Lutaml::Xml::Namespace
        uri "http://www.w3.org/2007/XMLSchema-versioning"
        prefix_default "vc"

        documentation <<~DOC
          W3C XML Schema Versioning namespace (XSD 1.1 §C.1).

          Attributes: vc:minVersion, vc:maxVersion, vc:typeAvailable,
          vc:facetAvailable, vc:disallowedReplacement and friends mark
          the schema dialect a component requires.
        DOC
      end
    end
  end
end
