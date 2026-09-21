# frozen_string_literal: true

require "spec_helper"

# Attribute identity is (namespace URI, local name) — lutaml-model#841.
# Where matching previously resolved silently by order (document order
# in the lenient recovery, array order in alias lists), several
# distinct matches are an ambiguity: no value binds and the collision
# is surfaced on stderr.
module AttributeAmbiguitySurfaceSpec
  # Lenient recovery: sole-claimant rule spelled URI:local while the
  # document's prefixes stay undeclared (#754 recovery case).
  class LenientProbe < Lutaml::Model::Serializable
    attribute :ext, :string

    xml do
      element "probe"
      map_attribute "urn:example:v:ext", to: :ext
    end
  end

  # Alias list: spelling variants of one name — at most one may occur.
  class AliasProbe < Lutaml::Model::Serializable
    attribute :status, :string

    xml do
      element "probe"
      map_attribute %w[status product-status], to: :status
    end
  end
end

RSpec.describe "Ambiguous attribute matches surface instead of resolving by order" do
  describe "lenient local-name recovery" do
    it "recovers the single undeclared-prefix attribute" do
      probe = AttributeAmbiguitySurfaceSpec::LenientProbe.from_xml(
        %(<probe v:ext="1"/>),
      )
      expect(probe.ext).to eq("1")
    end

    it "binds no value when several same-local attributes match" do
      expect do
        probe = AttributeAmbiguitySurfaceSpec::LenientProbe.from_xml(
          %(<probe v:ext="1" w:ext="2"/>),
        )
        expect(probe.ext).to be_nil
      end.to output(/ambiguous attribute/i).to_stderr
    end

    it "prefers the exact qualified match when the prefix IS declared" do
      probe = AttributeAmbiguitySurfaceSpec::LenientProbe.from_xml(
        %(<probe xmlns:v="urn:example:v" v:ext="1" w:ext="2"/>),
      )
      expect(probe.ext).to eq("1")
    end
  end

  describe "alias lists" do
    it "reads the single present alias" do
      probe = AttributeAmbiguitySurfaceSpec::AliasProbe.from_xml(
        %(<probe product-status="draft"/>),
      )
      expect(probe.status).to eq("draft")

      probe = AttributeAmbiguitySurfaceSpec::AliasProbe.from_xml(
        %(<probe status="open"/>),
      )
      expect(probe.status).to eq("open")
    end

    it "binds no value when two aliases are simultaneously present" do
      expect do
        probe = AttributeAmbiguitySurfaceSpec::AliasProbe.from_xml(
          %(<probe status="open" product-status="draft"/>),
        )
        expect(probe.status).to be_nil
      end.to output(/ambiguous attribute aliases/i).to_stderr
    end
  end
end
