# frozen_string_literal: true

require "spec_helper"

# lutaml-model#154: HTML named/numeric entities decode only for
# mappings that opt in via `html_entities` — XML otherwise keeps
# undefined entities literal.
RSpec.describe "Opt-in HTML entity decoding" do
  context "when the mapping opts in" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :t, :string

        xml do
          element "doc"
          map_element "t", to: :t
          html_entities
        end
      end
    end

    it "decodes named and numeric entities in element text" do
      parsed = model_class.from_xml("<doc><t>a &amp; b &#8212; c &copy; d</t></doc>")
      expect(parsed.t).to eq("a & b — c © d")
    end
  end

  context "when the mapping does not opt in" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :t, :string

        xml do
          element "doc"
          map_element "t", to: :t
        end
      end
    end

    it "keeps undefined entities literal" do
      parsed = model_class.from_xml("<doc><t>a &amp; b &copy; d</t></doc>")
      expect(parsed.t).to eq("a & b &copy; d")
    end
  end
end
