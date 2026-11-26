# frozen_string_literal: true

require "spec_helper"

RSpec.describe "`model` declaration under every XML adapter (#1208)" do
  let(:xml) { "<book><title>Hi</title></book>" }

  # Mirrors the issue repro: the Serializable class declares `model
  # BookData`; the helpers live on the plain model class.
  let(:build_classes) do
    stub_const("BookData", Class.new do
      attr_accessor :title

      def shout = title.upcase
    end)
    stub_const("Book", Class.new(Lutaml::Model::Serializable) do
      model BookData

      attribute :title, :string

      xml do
        element "book"
        map_element "title", to: :title
      end
    end)
  end

  it "returns the declared model class on the configured adapter" do
    build_classes

    book = Book.from_xml(xml)

    expect(book).to be_a(BookData)
    expect(book.shout).to eq("HI")
    expect(book.title).to eq("Hi")
  end

  it "returns the declared model class on the leptris lane", if: defined?(Leptris) do
    build_classes
    previous = Lutaml::Model::Config.xml_adapter_type
    Lutaml::Model::Config.xml_adapter_type = :leptris

    book = Book.from_xml(xml)

    expect(book).to be_a(BookData)
    expect(book.shout).to eq("HI")
  ensure
    Lutaml::Model::Config.xml_adapter_type = previous
  end

  it "returns the declared model class on the nokogiri lane", if: defined?(Nokogiri) do
    build_classes
    previous = Lutaml::Model::Config.xml_adapter_type
    Lutaml::Model::Config.xml_adapter_type = :nokogiri

    book = Book.from_xml(xml)

    expect(book).to be_a(BookData)
    expect(book.shout).to eq("HI")
  ensure
    Lutaml::Model::Config.xml_adapter_type = previous
  end

  it "round-trips a model-class instance through to_xml" do
    build_classes

    data = BookData.new
    data.title = "Hi"

    emitted = Book.to_xml(data)
    expect(emitted).to include("<title>Hi</title>")

    reparsed = Book.from_xml(emitted)
    expect(reparsed).to be_a(BookData)
    expect(reparsed.title).to eq("Hi")
  end
end
