# frozen_string_literal: true

require "spec_helper"

# The leptris emission read `attribute_order` on every instance
# unconditionally; plain `model` classes did not carry the accessor,
# so serializing a parsed document crashed with NoMethodError while
# the nokogiri lane serialized the same document (#1232).
RSpec.describe "leptris emission vs plain model instances (#1232)" do
  let(:plain_class) do
    Class.new do
      attr_accessor :title

      def initialize(title = nil)
        @title = title
      end
    end
  end

  let(:mapper) do
    plain = plain_class

    Class.new(Lutaml::Model::Serializable) do
      model plain
      attribute :title, :string

      xml do
        element "pub"
        map_attribute "title", to: :title
      end
    end
  end

  it "installs the attribute_order accessor on plain model classes" do
    mapper # materialize: the accessor install runs when `model` binds

    aggregate_failures do
      expect(plain_class.method_defined?(:attribute_order)).to be(true)
      expect(plain_class.method_defined?(:attribute_order=)).to be(true)
    end
  end

  it "serializes a parsed document through leptris without the face read crash" do
    Lutaml::Model::Config.with_adapter(xml: :leptris) do
      instance = mapper.from_xml(%(<pub title="hello"/>))

      expect(mapper.to_xml(instance)).to include('<pub title="hello"/>')
    end
  end
end
