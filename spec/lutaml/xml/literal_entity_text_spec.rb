# frozen_string_literal: true

require "spec_helper"
require "nokogiri"

module LiteralEntityTextSpec
  class Content < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "content"
      map_content to: :value
    end
  end

  class Mixed < Lutaml::Model::Serializable
    attribute :value, :string, collection: true
    attribute :bold, :string, collection: true

    xml do
      element "mixed"
      mixed_content
      map_content to: :value
      map_element "b", to: :bold
    end
  end

  class Child < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "child"
      map_element "value", to: :value
    end
  end
end

RSpec.describe "Literal entity names in XML text" do
  around do |example|
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) { example.run }
  end

  text_values = ["&bigotimes;", "A & B", "<tag>", "©\u00a0"]
  [LiteralEntityTextSpec::Content, LiteralEntityTextSpec::Child].each do |model|
    text_values.each do |text|
      it "preserves #{text.inspect} as #{model.name} character data" do
        instance = model.new(value: text)
        output = instance.to_xml(escape_entities: true)
        parsed = Nokogiri::XML(output, &:strict)

        node = model == LiteralEntityTextSpec::Child ? parsed.at_xpath("/child/value") : parsed.root
        expect(node.text).to eq(text)
        expect(model.from_xml(output).value).to eq(text)
      end
    end
  end

  it "escapes literal tokens and mapped children in ordered content" do
    input = "<mixed>&amp;copy;<b>&amp;bigotimes;</b>&amp;nbsp;</mixed>"
    instance = LiteralEntityTextSpec::Mixed.from_xml(input)
    output = instance.to_xml(escape_entities: true)
    parsed = Nokogiri::XML(output, &:strict)

    expect(parsed.root.text).to eq("&copy;&bigotimes;&nbsp;")
    expect(parsed.at_xpath("/mixed/b").text).to eq("&bigotimes;")
    expect(LiteralEntityTextSpec::Mixed.from_xml(output).value).to eq(instance.value)
  end

  it "preserves the legacy named-entity output when not opted in" do
    instance = LiteralEntityTextSpec::Content.new(value: "&copy;")

    expect(instance.to_xml).to include("&copy;")
    expect(instance.to_xml(escape_entities: false)).to eq(instance.to_xml)
  end

  it "keeps an escaped entity name escaped after parsing" do
    instance = LiteralEntityTextSpec::Content.from_xml(
      "<content>&amp;bigotimes;</content>",
    )

    expect(instance.value).to eq("&bigotimes;")
    expect(instance.to_xml(escape_entities: true)).to include("&amp;bigotimes;")
  end
end
