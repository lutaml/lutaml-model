# frozen_string_literal: true

require "spec_helper"

# add_xml_fragment / add_element(String) in a map_content hook must write the
# same markup as in a map_element hook, on every adapter (Leptris, the
# default outside the suite's nokogiri pin, used to write the mapped string as
# escaped text and truncate it at a NUL).
RSpec.describe "Callback markup insertion across adapters" do
  def model_for(kind, inserter)
    Class.new(Lutaml::Model::Serializable) do
      attribute :c, :string
      xml do
        element "r"
        if kind == :content
          map_content to: :c, with: { from: :read_c, to: :write_c }
        else
          map_element "e", to: :c, with: { from: :read_c, to: :write_c }
        end
      end

      define_method(:read_c) { |model, value| model.c = value }
      define_method(:write_c) { |model, parent, doc| doc.public_send(inserter, parent, model.c) }
    end
  end

  def squeezed(xml)
    xml.gsub(/>\s+</, "><").strip
  end

  inserters = %i[add_xml_fragment add_element]

  %i[nokogiri ox rexml oga leptris].each do |adapter|
    describe "with the #{adapter} adapter" do
      around do |example|
        previous = Lutaml::Model::Config.xml_adapter_type
        Lutaml::Model::Config.xml_adapter_type = adapter
        example.run
      ensure
        Lutaml::Model::Config.xml_adapter_type = previous
      end

      inserters.each do |inserter|
        it "#{inserter} inserts markup from a content hook like an element hook" do
          content = squeezed(model_for(:content, inserter).new(c: "a<i>b</i> tail").to_xml)
          element = squeezed(model_for(:element, inserter).new(c: "a<i>b</i> tail").to_xml)

          expect(content).to eq("<r>a<i>b</i> tail</r>")
          expect(element).to eq(content)
        end

        it "#{inserter} keeps plain text from a content hook" do
          expect(squeezed(model_for(:content, inserter).new(c: "m").to_xml)).to eq("<r>m</r>")
        end
      end

      it "refuses a NUL in a content hook fragment instead of truncating it" do
        expect { model_for(:content, :add_xml_fragment).new(c: "a\u0000b").to_xml }.to raise_error(ArgumentError, /null byte/)
      end
    end
  end

  it "keeps the text of add_element(parent, String) for non-LML callers" do
    expect(squeezed(model_for(:element, :add_element).new(c: "m").to_xml)).to include("m")
  end
end
