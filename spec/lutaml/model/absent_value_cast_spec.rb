# frozen_string_literal: true

require "spec_helper"

# Issue #795: two documented parse contracts flipped in 0.8.34 and
# are pinned here.
RSpec.describe "absent-value parse contracts (#795)" do
  # ST_OnOff-style: an absent attribute is semantically false.
  let(:on_off) do
    Class.new(Lutaml::Model::Type::Boolean) do
      def self.name = "OnOff795"

      def self.cast(value, _options = {})
        return false if value.nil?

        super
      end
    end
  end

  let(:doc_model) do
    type = on_off
    Class.new(Lutaml::Model::Serializable) do
      def self.name = "Doc795"

      attribute :flag, type
      xml do
        element "doc"
        map_attribute "flag", to: :flag
      end
    end
  end

  it "casts absent attributes through the type (absent boolean is false)" do
    expect(doc_model.from_xml("<doc/>").flag).to be(false)
  end

  it "still casts present attributes" do
    expect(doc_model.from_xml('<doc flag="1"/>').flag).to be(true)
    expect(doc_model.from_xml('<doc flag="0"/>').flag).to be(false)
  end

  it "does not mint phantom instances for absent values" do
    # The phantom rule (dd0c06a5) still holds: a no-data cast may MAP
    # to a scalar (the boolean above) but never MINT a typed instance.
    eager = Class.new(Lutaml::Model::Type::String) do
      def self.name = "Eager795"

      def self.cast(value, _options = {})
        obj = allocate
        obj.instance_variable_set(:@value, value || "phantom")
        obj
      end
    end
    model = Class.new(Lutaml::Model::Serializable) do
      def self.name = "Phantom795"

      attribute :e, eager
      xml do
        element "p"
        map_element "e", to: :e
      end
    end

    expect(model.from_xml("<p/>").e).to be_nil
    expect(model.new.to_xml).not_to include("<e>")
  end

  describe "element_order frozen after parse" do
    let(:model) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name = "Order795"

        attribute :flag, :string
        xml do
          element "doc"
          map_attribute "flag", to: :flag
        end
      end
    end

    it "hands back the frozen DOM-shared array" do
      parsed = model.from_xml('<doc flag="1"><child>a</child></doc>')

      expect(parsed.element_order).to be_frozen
      expect { parsed.element_order << "x" }.to raise_error(FrozenError)
    end

    it "supports thaw-on-demand maintenance" do
      parsed = model.from_xml('<doc flag="1"><child>a</child></doc>')
      parsed.element_order = parsed.element_order + ["x"]

      expect(parsed.element_order.last).to eq("x")
    end
  end
end
