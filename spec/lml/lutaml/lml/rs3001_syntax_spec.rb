# frozen_string_literal: true

require "spec_helper"

def parse_rs3001_document(src)
  Lutaml::Lml.parse_document(StringIO.new(src))
end

RSpec.describe "RS 3001 syntax" do
  describe "§Comment" do
    it "strips // comments while preserving // inside string literals" do
      doc = parse_rs3001_document(<<~LML)
        // leading comment
        instances {
          Product "p" {
            url = "http://example.com//x" // tail comment
          }
        }
      LML
      attr = doc.instances.instances.first.attributes.find { |a| a.name == "url" }
      expect(attr.value.to_s).to eq("http://example.com//x")
    end

    it "strips multi-line /* */ block comments" do
      doc = parse_rs3001_document(<<~LML)
        /* block
           comment */
        class Materials::CeramicTile { }
      LML
      expect(doc.classes.map(&:name)).to eq(["Materials::CeramicTile"])
    end

    it "raises on an unterminated block comment" do
      expect { parse_rs3001_document("class C { /* oops\n }\n") }
        .to raise_error(Lutaml::Lml::Error, /unterminated block comment/)
    end
  end

  describe "§Package" do
    it "parses a package with nested classes and enums" do
      doc = parse_rs3001_document(<<~LML)
        // leading comment
        package Ceramics {
          class Tile { }
          enum Glaze { celadon }
        }
      LML
      pkg = doc.packages.first
      expect(pkg.name).to eq("Ceramics")
      expect(pkg.classes.map(&:name)).to eq(["Tile"])
      expect(pkg.enums.map(&:name)).to eq(["Glaze"])
    end
  end

  describe "§Instance" do
    it "parses the quoted-name instance form with an explicit type" do
      doc = parse_rs3001_document(<<~LML)
        instances {
          instance "square" Tile {
            url = "http://example.com//x"
          }
        }
      LML
      inst = doc.instances.instances.first
      expect(inst.type).to eq("Tile")
      expect(inst.attributes.map { |a| [a.name, a.value.to_s] })
        .to eq([["url", "http://example.com//x"]])
    end
  end

  describe "§Namespacing" do
    it "parses double-colon scoped class names" do
      doc = parse_rs3001_document("class Materials::CeramicTile { }\n")
      expect(doc.classes.map(&:name)).to eq(["Materials::CeramicTile"])
    end
  end
end
