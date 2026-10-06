# frozen_string_literal: true

require "spec_helper"

module WriterAssigned
  class Plain < Lutaml::Model::Serializable
    attribute :code, :string
    attribute :text, :string

    xml do
      element "probe"
      map_element "code", to: :code
      map_element "text", to: :text
    end

    def code=(val)
      super
      self.text = "derived-#{val}" if val
    end
  end

  class Defaulted < Lutaml::Model::Serializable
    attribute :code, :string
    attribute :text, :string, default: -> { "" }

    xml do
      element "probe"
      map_element "code", to: :code
      map_element "text", to: :text
    end

    def code=(val)
      super
      self.text = "derived-#{val}" if val
    end
  end
end

# lutaml-model#922: a custom writer that assigns a *different* attribute
# mid-parse (relaton's Relaton::Bib::ICS populates <text> from the Isoics
# dataset inside code=) must survive the deserializer's unmatched-rule
# handling: the default seeding in Initialization#instantiate and the
# unmatched-rule replay must never overwrite a value a writer assigned.
RSpec.describe "attributes assigned inside another attribute's writer" do
  %i[Plain Defaulted].each do |klass_name|
    describe "with #{klass_name.to_s.downcase} text attribute" do
      let(:klass) { WriterAssigned.const_get(klass_name) }

      it "keeps the derived value through from_xml" do
        instance = klass.from_xml("<probe><code>67.060</code></probe>")

        expect(instance.text).to eq("derived-67.060")
      end

      it "renders the derived value on to_xml" do
        instance = klass.from_xml("<probe><code>67.060</code></probe>")

        expect(instance.to_xml).to include("<text>derived-67.060</text>")
      end
    end
  end
end
