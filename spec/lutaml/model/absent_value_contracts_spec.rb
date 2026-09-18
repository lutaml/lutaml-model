# frozen_string_literal: true

require "spec_helper"

# The 0.8.33 parse contracts restored after #795: a custom type's cast
# sees an absent attribute's nil (ST_OnOff booleans — an absent flag is
# semantically false), and the parsed element_order array is frozen
# (consumers build thaw-on-demand helpers on that).
RSpec.describe "absent-value and order contracts" do
  before do
    stub_const("OnOff", Class.new(Lutaml::Model::Type::Boolean) do
      def self.cast(value, _options = {})
        return false if value.nil?

        super
      end
    end)

    stub_const("Doc", Class.new(Lutaml::Model::Serializable) do
      attribute :flag, OnOff
      xml do
        element "doc"
        map_attribute "flag", to: :flag
      end
    end)
  end

  it "casts an absent attribute through the type (nil -> false)" do
    expect(Doc.from_xml("<doc/>").flag).to be(false)
  end

  it "still casts a present attribute" do
    expect(Doc.from_xml('<doc flag="0"/>').flag).to be(false)
    expect(Doc.from_xml('<doc flag="1"/>').flag).to be(true)
  end

  it "hands the parsed element_order back frozen" do
    expect(Doc.from_xml('<doc flag="1"/>').element_order).to be_frozen
  end

  it "does not manufacture typed instances from nothing" do
    stub_const("PhantomType", Class.new(Lutaml::Model::Type::String) do
      # Value#initialize casts what it is given, so a cast that
      # constructs has to bypass it (see phantom_value_spec's Eager).
      def initialize(value) # rubocop:disable Lint/MissingSuper
        @value = value
      end

      def self.cast(value, _options = {})
        return value if value.is_a?(PhantomType)

        new("phantom(#{value.inspect})")
      end
    end)
    stub_const("PhantomDoc", Class.new(Lutaml::Model::Serializable) do
      attribute :phantom, PhantomType
      xml do
        element "k"
        map_attribute "p", to: :phantom
      end
    end)

    expect(PhantomDoc.from_xml("<k/>").phantom).to be_nil
  end
end
