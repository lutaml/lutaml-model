# frozen_string_literal: true

require "spec_helper"

# A hand-written content callback inserts raw markup with
# doc.add_xml_fragment(parent, fragment). The fragment's text and entities
# must survive exactly, in document order, and markup must not be escaped.
RSpec.describe "CustomMethodWrapper raw fragment insertion" do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string

      xml do
        element "raw"
        map_content to: :content, with: { from: :read_noop, to: :write_raw }
      end

      def read_noop(**); end

      def write_raw(model, parent, doc)
        doc.add_xml_fragment(parent, model.content)
      end
    end
  end

  def written(fragment)
    model_class.new(content: fragment).to_xml.gsub(/>\s+</, "><").strip
  end

  {
    "plain text" => ["m", "<raw>m</raw>"],
    "text with a space" => ["kg m", "<raw>kg m</raw>"],
    "an entity in plain text" => ["x &amp; y", "<raw>x &amp; y</raw>"],
    "leading text before an element" => ["a<i>b</i>", "<raw>a<i>b</i></raw>"],
    "trailing text after an element" => ["<i>x</i> tail", "<raw><i>x</i> tail</raw>"],
    "an entity inside an element" => ["<i>m &amp; n</i>", "<raw><i>m &amp; n</i></raw>"],
    "mixed content in document order" => ["<p>t <b>b</b> u</p>", "<raw><p>t <b>b</b> u</p></raw>"],
    "two sibling elements" => ["<b>1</b><i>2</i>", "<raw><b>1</b><i>2</i></raw>"],
  }.each do |label, (fragment, expected)|
    it "writes #{label} without escaping markup or losing text" do
      expect(written(fragment)).to eq(expected)
    end
  end

  it "writes an empty fragment as an empty element" do
    expect(written("")).to eq("<raw/>")
  end
end
