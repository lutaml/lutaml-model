# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XmlElement" do
  describe "#text" do
    context "when only text is present" do
      let(:element) { create_element("name", text: "something") }

      it "returns text" do
        expect(element.text).to eq("something")
      end
    end

    context "when single text node is present" do
      let(:element) do
        create_element(
          "name",
          children: [
            create_element("text", text: "John Doe"),
          ],
        )
      end

      it "returns single string" do
        expect(element.text).to eq("John Doe")
      end
    end

    context "when multiple text nodes are present" do
      let(:element) do
        create_element(
          "name",
          children: [
            create_element("text", text: "John"),
            create_element("text", text: "\n"),
            create_element("text", text: "Doe"),
          ],
        )
      end

      it "returns all text elements array" do
        expect(element.text).to eq(["John", "\n", "Doe"])
      end
    end
  end

  describe "#cdata" do
    context "when only cdata is present" do
      let(:element) { create_element("name", text: "something") }

      it "returns cdata" do
        expect(element.cdata).to eq("something")
      end
    end

    context "when single cdata node is present" do
      let(:element) do
        create_element(
          "name",
          children: [
            create_element("#cdata-section", text: "John Doe"),
          ],
        )
      end

      it "returns single string" do
        expect(element.cdata).to eq("John Doe")
      end
    end

    context "when multiple cdata nodes are present" do
      let(:element) do
        create_element(
          "name",
          children: [
            create_element("#cdata-section", text: "John"),
            create_element("#cdata-section", text: "\n"),
            create_element("#cdata-section", text: "Doe"),
          ],
        )
      end

      it "returns all cdata elements array" do
        expect(element.cdata).to eq(["John", "\n", "Doe"])
      end
    end
  end

  def create_element(name, attributes: {}, children: [], text: "")
    Lutaml::Model::Xml::XmlElement.new(name, attributes, children, text)
  end
end
