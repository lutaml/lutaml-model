# frozen_string_literal: true

require "spec_helper"

# from_xml builds a custom-initialize class through its constructor so the
# class's own internal state exists. Its attributes must still come out of
# the parse exactly as they do for the same class on the standard
# initializer: constructor-seeded defaults are not values the document
# set, so an absent render_default: false element stays absent.
RSpec.describe "XML deserialization of a custom-initialize class" do
  let(:standard) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :bidi, :boolean, default: -> { false }

      xml do
        element "para"
        map_element "name", to: :name
        map_element "bidi", to: :bidi
      end
    end
  end

  let(:custom) do
    Class.new(standard) do
      def initialize(*args, **kwargs)
        @internal = :ready
        super
      end

      attr_reader :internal
    end
  end

  before do
    stub_const("XmlConstructorDefaultsStandard", standard)
    stub_const("XmlConstructorDefaultsCustom", custom)
  end

  it "runs the class's own initialize" do
    expect(custom.from_xml("<para><name>a</name></para>").internal).to eq(:ready)
  end

  it "keeps an absent defaulted element absent on round trip" do
    xml = custom.from_xml("<para><name>a</name></para>").to_xml

    expect(xml).not_to include("bidi")
  end

  [
    "<para><name>a</name></para>",
    "<para><name>a</name><bidi>true</bidi></para>",
    "<para><name>a</name><bidi>false</bidi></para>",
  ].each do |input|
    it "parses #{input} the same as the standard initializer" do
      expected = standard.from_xml(input)
      actual = custom.from_xml(input)

      expect([actual.bidi, actual.to_xml])
        .to eq([expected.bidi, expected.to_xml])
    end
  end
end
