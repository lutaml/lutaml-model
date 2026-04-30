# frozen_string_literal: true

require_relative "spec_helper"
require "lutaml/xml/schema/xsd"

RSpec.describe Lutaml::Xml::Schema::Xsd::Glob do
  describe ".schema_mappings" do
    after do
      # Clean up after each test
      described_class.schema_mappings = nil
    end

    it "returns empty hash by default" do
      expect(described_class.schema_mappings).to eq([])
    end

    it "allows setting mappings" do
      mappings = [{ from: "http://example.com/schema.xsd",
                    to: "/local/schema.xsd" }]
      described_class.schema_mappings = mappings
      expect(described_class.schema_mappings).to eq(mappings)
    end

    it "handles nil assignment by setting empty hash" do
      described_class.schema_mappings = nil
      expect(described_class.schema_mappings).to eq([])
    end

    it "preserves mappings across multiple accesses" do
      mappings = [{ from: "http://example.com/schema.xsd",
                    to: "/local/schema.xsd" }]
      described_class.schema_mappings = mappings
      expect(described_class.schema_mappings).to eq(mappings)
      expect(described_class.schema_mappings).to eq(mappings)
    end
  end

  describe ".resolve_schema_location" do
    after do
      described_class.schema_mappings = nil
    end

    context "with empty mappings" do
      before do
        described_class.schema_mappings = []
      end

      it "returns original location" do
        location = "http://example.com/schema.xsd"
        expect(described_class.send(:resolve_schema_location,
                                    location)).to eq(location)
      end
    end

    context "with exact string match" do
      before do
        described_class.schema_mappings = [
          { from: "http://schemas.opengis.net/gml/3.1.1/base/gml.xsd",
            to: "/local/gml.xsd" },
          { from: "../../external/schema.xsd",
            to: "/absolute/path/schema.xsd" },
        ]
      end

      it "resolves exact HTTP URL match" do
        location = "http://schemas.opengis.net/gml/3.1.1/base/gml.xsd"
        expect(described_class.send(:resolve_schema_location,
                                    location)).to eq("/local/gml.xsd")
      end

      it "resolves exact relative path match" do
        location = "../../external/schema.xsd"
        expect(described_class.send(:resolve_schema_location,
                                    location)).to eq("/absolute/path/schema.xsd")
      end

      it "returns original for non-matching location" do
        location = "http://example.com/other.xsd"
        expect(described_class.send(:resolve_schema_location,
                                    location)).to eq(location)
      end
    end

    context "with regex pattern match" do
      before do
        described_class.schema_mappings = [
          { from: %r{http://schemas\.opengis\.net/citygml/(.+)},
            to: '/local/citygml/\\1' },
          { from: %r{http://schemas\.opengis\.net/gml/(.+)},
            to: '/local/gml/\\1' },
        ]
      end

      it "resolves using regex pattern" do
        location = "http://schemas.opengis.net/citygml/2.0/cityGMLBase.xsd"
        resolved = described_class.send(:resolve_schema_location, location)
        expect(resolved).to eq("/local/citygml/2.0/cityGMLBase.xsd")
      end

      it "resolves using second regex pattern if first doesn't match" do
        location = "http://schemas.opengis.net/gml/3.1.1/base/gml.xsd"
        resolved = described_class.send(:resolve_schema_location, location)
        expect(resolved).to eq("/local/gml/3.1.1/base/gml.xsd")
      end

      it "returns original if no pattern matches" do
        location = "http://example.com/other.xsd"
        expect(described_class.send(:resolve_schema_location,
                                    location)).to eq(location)
      end
    end

    context "with mixed exact and regex mappings" do
      before do
        described_class.schema_mappings = [
          { from: "http://schemas.opengis.net/gml/3.1.1/base/gml.xsd",
            to: "/exact/match/gml.xsd" },
          { from: %r{http://schemas\.opengis\.net/gml/(.+)},
            to: '/pattern/match/\\1' },
        ]
      end

      it "prioritizes exact match over regex pattern" do
        location = "http://schemas.opengis.net/gml/3.1.1/base/gml.xsd"
        resolved = described_class.send(:resolve_schema_location, location)
        expect(resolved).to eq("/exact/match/gml.xsd")
      end

      it "uses regex pattern when exact match not found" do
        location = "http://schemas.opengis.net/gml/3.2/other.xsd"
        resolved = described_class.send(:resolve_schema_location, location)
        expect(resolved).to eq("/pattern/match/3.2/other.xsd")
      end
    end

    context "with multiple regex patterns" do
      before do
        described_class.schema_mappings = [
          { from: %r{http://schemas\.opengis\.net/citygml/(.+)},
            to: '/first/pattern/\\1' },
          { from: %r{http://schemas\.opengis\.net/(.+)},
            to: '/second/pattern/\\1' },
        ]
      end

      it "uses first matching pattern" do
        location = "http://schemas.opengis.net/citygml/2.0/base.xsd"
        resolved = described_class.send(:resolve_schema_location, location)
        expect(resolved).to eq("/first/pattern/2.0/base.xsd")
      end

      it "uses second pattern if first doesn't match" do
        location = "http://schemas.opengis.net/gml/3.1.1/base.xsd"
        resolved = described_class.send(:resolve_schema_location, location)
        expect(resolved).to eq("/second/pattern/gml/3.1.1/base.xsd")
      end
    end
  end

  describe ".include_schema" do
    let(:base_dir) do
      File.expand_path("../../../../fixtures/xml/schema/xsd", __dir__)
    end
    let(:test_schema_path) { File.join(base_dir, "metaschema.xsd") }

    before do
      described_class.path_or_url(base_dir)
    end

    after do
      described_class.schema_mappings = nil
      described_class.send(:nullify_location)
    end

    context "with absolute path mapping" do
      before do
        described_class.schema_mappings = [
          { from: "http://example.com/schema.xsd", to: test_schema_path },
        ]
      end

      it "reads from mapped absolute path" do
        content = described_class.include_schema("http://example.com/schema.xsd")
        expect(content).to be_a(String)
        expect(content).to include("<?xml")
      end
    end

    context "with unmapped location" do
      it "resolves relative to base location" do
        content = described_class.include_schema("metaschema.xsd")
        expect(content).to be_a(String)
        expect(content).to include("<?xml")
      end
    end

    context "with regex pattern mapping" do
      before do
        # Use forward slashes for cross-platform compatibility in regex patterns
        # Ruby's File.join uses backslashes on Windows, but forward slashes work
        # universally in file paths on all platforms including Windows
        pattern_target = "#{base_dir.tr('\\', '/')}/\\1"
        described_class.schema_mappings = [
          { from: %r{http://example\.com/schemas/(.+)},
            to: pattern_target },
        ]
      end

      it "reads from pattern-resolved path" do
        content = described_class.include_schema("http://example.com/schemas/metaschema.xsd")
        expect(content).to be_a(String)
        expect(content).to include("<?xml")
      end
    end
  end

  describe ".path_or_url" do
    after do
      described_class.send(:nullify_location)
    end

    it "sets path for local directory" do
      path = File.expand_path("../../fixtures", __dir__)
      described_class.path_or_url(path)
      expect(described_class.path?).to be true
      expect(described_class.url?).to be false
    end

    it "sets url for HTTP location" do
      url = "http://example.com/schemas/"
      described_class.path_or_url(url)
      expect(described_class.url?).to be true
      expect(described_class.path?).to be false
    end

    it "sets url for HTTPS location" do
      url = "https://example.com/schemas/"
      described_class.path_or_url(url)
      expect(described_class.url?).to be true
      expect(described_class.path?).to be false
    end

    it "uses the containing URL when location points to a schema file" do
      described_class.path_or_url("https://example.com/schemas/root.xsd")

      expect(described_class.schema_location_path("child.xsd"))
        .to eq("https://example.com/schemas/child.xsd")
    end

    it "handles nil location" do
      described_class.path_or_url(nil)
      expect(described_class.location?).to be false
    end
  end

  describe "error handling" do
    let(:base_dir) { File.expand_path("../../fixtures", __dir__) }

    before do
      described_class.path_or_url(base_dir)
    end

    after do
      described_class.schema_mappings = nil
      described_class.send(:nullify_location)
    end

    context "when mapped file does not exist" do
      it "raises error with helpful message for absolute path mapping" do
        nonexistent_path = "/nonexistent/path/to/schema.xsd"
        described_class.schema_mappings = [
          { from: "http://example.com/schema.xsd", to: nonexistent_path },
        ]

        expect do
          described_class.include_schema("http://example.com/schema.xsd")
        end.to raise_error(
          Lutaml::Xml::Schema::Xsd::Error,
          /Mapped schema file not found: #{Regexp.escape(nonexistent_path)}/,
        )
      end

      it "includes original location in error message" do
        nonexistent_path = "/nonexistent/path/to/schema.xsd"
        described_class.schema_mappings = [
          { from: "http://example.com/schema.xsd", to: nonexistent_path },
        ]

        expect do
          described_class.include_schema("http://example.com/schema.xsd")
        end.to raise_error(
          Lutaml::Xml::Schema::Xsd::Error,
          %r{original location: http://example\.com/schema\.xsd},
        )
      end
    end

    context "when schema file does not exist" do
      it "raises error with helpful message" do
        expect do
          described_class.include_schema("nonexistent_schema.xsd")
        end.to raise_error(
          Lutaml::Xml::Schema::Xsd::Error,
          /Schema file not found:.*nonexistent_schema\.xsd/,
        )
      end

      it "includes original location in error message" do
        expect do
          described_class.include_schema("../../missing/schema.xsd")
        end.to raise_error(
          Lutaml::Xml::Schema::Xsd::Error,
          %r{original location:.*missing/schema\.xsd},
        )
      end
    end
  end
end
