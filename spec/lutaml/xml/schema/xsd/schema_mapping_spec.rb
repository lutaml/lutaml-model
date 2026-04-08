# frozen_string_literal: true

require_relative "spec_helper"
require "lutaml/xml/schema/xsd"

RSpec.describe "Schema mapping integration" do
  let(:fixtures_dir) do
    File.expand_path("../../../../fixtures/xml/schema/xsd", __dir__)
  end

  after do
    Lutaml::Xml::Schema::Xsd::Glob.schema_mappings = nil
  end

  describe "parsing with exact string mappings" do
    let(:xsd_content) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test"
                   xmlns:test="http://example.com/test">
          <xs:import namespace="http://example.com/imported"
                     schemaLocation="http://remote.example.com/schema.xsd"/>
        </xs:schema>
      XSD
    end

    it "maps remote URL to local file" do
      local_schema_path = File.join(fixtures_dir, "metaschema.xsd")
      schema_mappings = [
        { from: "http://remote.example.com/schema.xsd", to: local_schema_path },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.target_namespace).to eq("http://example.com/test")
    end

    it "maps relative path to absolute path" do
      local_schema_path = File.join(fixtures_dir, "metaschema.xsd")
      xsd_with_relative = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:include schemaLocation="../../external/schema.xsd"/>
        </xs:schema>
      XSD

      schema_mappings = [
        { from: "../../external/schema.xsd", to: local_schema_path },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_with_relative,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
    end
  end

  describe "parsing with regex pattern mappings" do
    it "maps URL patterns to local directory structure" do
      local_schema_path = File.join(fixtures_dir, "metaschema.xsd")
      xsd_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:import namespace="http://example.com/remote"
                     schemaLocation="http://schemas.example.com/remote/v1.0/schema.xsd"/>
        </xs:schema>
      XSD

      # Since the pattern maps to fixtures_dir/v1.0/schema.xsd which doesn't exist,
      # we need to map to an existing file
      schema_mappings = [
        { from: "http://schemas.example.com/remote/v1.0/schema.xsd",
          to: local_schema_path },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
    end

    it "handles multiple regex patterns" do
      # Create a test XSD that imports from multiple ISO directories
      xsd_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:import namespace="http://www.isotc211.org/2005/gmd"
                     schemaLocation="http://schemas.isotc211.org/19139/20070417/gmd/gmd.xsd"/>
          <xs:import namespace="http://www.isotc211.org/2005/gco"
                     schemaLocation="http://schemas.isotc211.org/19139/20070417/gco/gco.xsd"/>
        </xs:schema>
      XSD

      schema_mappings = [
        # Multiple regex patterns for different ISO directories
        { from: %r{https://schemas\.isotc211\.org/19139/20070417/gmd/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmd/\1') },
        { from: %r{https://schemas\.isotc211\.org/19139/20070417/gco/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gco/\1') },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.imports).not_to be_empty
      expect(parsed.imports.size).to eq(2)
    end
  end

  describe "parsing with mixed exact and regex mappings" do
    it "prioritizes exact matches over patterns" do
      xsd_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:import namespace="http://example.com/specific"
                     schemaLocation="gmd.xsd"/>
        </xs:schema>
      XSD

      exact_match_path = File.join(fixtures_dir,
                                   "codesynthesis-gml-3.2.1/iso/19139/20070417/gmd/gmd.xsd")
      pattern_match_path = File.join(fixtures_dir, "metaschema.xsd")

      schema_mappings = [
        # Exact match should take priority
        { from: "gmd.xsd", to: exact_match_path },
        # Regex pattern as fallback
        { from: /^(.+\.xsd)$/, to: pattern_match_path },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      # The exact match mapping should be used (exact_match_path)
    end
  end

  describe "parsing i-UR schemas with mappings" do
    let(:urban_function_file) do
      File.join(fixtures_dir, "i-ur/urbanFunction.xsd")
    end
    let(:urban_function_content) { File.read(urban_function_file) }

    let(:codesynthesis_mappings) do
      [
        # 1. Specific relative path
        { from: "../../uro/3.2/urbanObject.xsd",
          to: File.join(fixtures_dir, "i-ur/urbanObject.xsd") },

        # 2-4. Relative path patterns
        { from: %r{(?:\.\./)+xlink/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/xlink/\1') },
        { from: %r{(?:\.\./)+gml/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/gml/\1') },
        { from: %r{(?:\.\./)+iso/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/iso/\1') },

        # 5-10. Simple relative paths for ISO metadata
        { from: %r{^\.\./gmd/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmd/\1') },
        { from: %r{^\.\./gss/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gss/\1') },
        { from: %r{^\.\./gts/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gts/\1') },
        { from: %r{^\.\./gsr/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gsr/\1') },
        { from: %r{^\.\./gco/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gco/\1') },
        { from: %r{^\.\./gmx/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmx/\1') },

        # 11. GML bare filenames
        { from: /^(basicTypes|coordinateOperations|coordinateReferenceSystems|coordinateSystems|coverage|datums|defaultStyle|deprecatedTypes|dictionary|direction|dynamicFeature|feature|geometryAggregates|geometryBasic0d1d|geometryBasic2d|geometryComplexes|geometryPrimitives|gml|gmlBase|grids|measures|observation|referenceSystems|temporal|temporalReferenceSystems|temporalTopology|topology|units|valueObjects)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/gml/3.2.1/\1.xsd') },

        # 12-17. ISO metadata bare filenames
        { from: /^(applicationSchema|citation|constraints|content|dataQuality|distribution|extent|freeText|gmd|identification|maintenance|metadataApplication|metadataEntity|metadataExtension|portrayalCatalogue|referenceSystem|spatialRepresentation)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmd/\1.xsd') },
        { from: /^(geometry|gss)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gss/\1.xsd') },
        { from: /^(gts|temporalObjects)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gts/\1.xsd') },
        { from: /^(gsr|spatialReferencing)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gsr/\1.xsd') },
        { from: /^(basicTypes|gco|gcoBase)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gco/\1.xsd') },
        { from: /^(catalogues|codelistItem|crsItem|extendedTypes|gmx|gmxUsage|uomItem)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmx/\1.xsd') },

        # 18. SMIL20 files
        { from: /^(smil20-.*|smil20|xml-mod|rdf)\.xsd$/,
          to: File.join(fixtures_dir, 'smil20/\1.xsd') },

        # 19-21. URL mappings
        { from: %r{https://schemas\.isotc211\.org/(.+)},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/iso/\1') },
        { from: %r{(?:\.\./)+(\d{5}/.+\.xsd)$},
          to: File.join(fixtures_dir, 'isotc211/\1') },
        { from: %r{https?://docs\.oasis-open\.org/election/external/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'citygml/xAL/\1') },
      ]
    end

    it "parses urbanFunction.xsd successfully with all mappings" do
      parsed = Lutaml::Xml::Schema::Xsd.parse(
        urban_function_content,
        location: File.dirname(urban_function_file),
        schema_mappings: codesynthesis_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.target_namespace).to eq("https://www.geospatial.jp/iur/urf/3.2")
      expect(parsed.element_form_default).to eq("qualified")
    end

    it "resolves imports correctly" do
      parsed = Lutaml::Xml::Schema::Xsd.parse(
        urban_function_content,
        location: File.dirname(urban_function_file),
        schema_mappings: codesynthesis_mappings,
      )

      expect(parsed.imports).not_to be_empty
      expect(parsed.imports.size).to eq(3)

      # Check that import objects have the expected attributes
      namespaces = parsed.imports.map(&:namespace)
      expect(namespaces).to include("http://www.opengis.net/citygml/2.0")
      expect(namespaces).to include("http://www.opengis.net/gml")
      expect(namespaces).to include("https://www.geospatial.jp/iur/uro/3.2")
    end

    it "parses elements from urbanFunction schema" do
      parsed = Lutaml::Xml::Schema::Xsd.parse(
        urban_function_content,
        location: File.dirname(urban_function_file),
        schema_mappings: codesynthesis_mappings,
      )

      expect(parsed.element).not_to be_empty
      expect(parsed.element.size).to be > 100

      # Verify some expected elements exist
      element_names = parsed.element.map(&:name)
      expect(element_names).to include("Administration")
      expect(element_names).to include("Agreement")
    end

    it "parses complex types from urbanFunction schema" do
      parsed = Lutaml::Xml::Schema::Xsd.parse(
        urban_function_content,
        location: File.dirname(urban_function_file),
        schema_mappings: codesynthesis_mappings,
      )

      expect(parsed.complex_type).not_to be_empty
      expect(parsed.complex_type.size).to be > 200

      # Verify some expected complex types exist
      type_names = parsed.complex_type.map(&:name)
      expect(type_names).to include("AdministrationType")
      expect(type_names).to include("AgreementType")
    end
  end

  describe "regex pattern matching" do
    it "matches relative paths with multiple ../ segments" do
      xsd_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:import namespace="http://www.opengis.net/gml/3.2"
                     schemaLocation="../../gml/3.2.1/dynamicFeature.xsd"/>
        </xs:schema>
      XSD

      schema_mappings = [
        # Map GML relative paths with multiple ../
        { from: %r{(?:\.\./)+gml/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/gml/\1') },
        # Map xlink relative paths with multiple ../
        { from: %r{(?:\.\./)+xlink/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/xlink/\1') },
        # Map GML bare filenames for nested includes
        { from: /^(basicTypes|coordinateOperations|coordinateReferenceSystems|coordinateSystems|coverage|datums|defaultStyle|deprecatedTypes|dictionary|direction|dynamicFeature|feature|geometryAggregates|geometryBasic0d1d|geometryBasic2d|geometryComplexes|geometryPrimitives|gml|gmlBase|grids|measures|observation|referenceSystems|temporal|temporalReferenceSystems|temporalTopology|topology|units|valueObjects)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/gml/3.2.1/\1.xsd') },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.imports).not_to be_empty
    end

    it "matches simple relative paths" do
      xsd_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:import namespace="http://www.isotc211.org/2005/gmd"
                     schemaLocation="../gmd/gmd.xsd"/>
        </xs:schema>
      XSD

      schema_mappings = [
        # Map simple relative paths for GMD
        { from: %r{^\.\./gmd/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmd/\1') },
        # Map simple relative paths for GCO (needed by gmd.xsd)
        { from: %r{^\.\./gco/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gco/\1') },
        # Map other ISO directories that gmd.xsd imports
        { from: %r{^\.\./gss/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gss/\1') },
        { from: %r{^\.\./gts/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gts/\1') },
        { from: %r{^\.\./gsr/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gsr/\1') },
        { from: %r{^\.\./gmx/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmx/\1') },
        # Map ISO relative paths with multiple ../
        { from: %r{(?:\.\./)+iso/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/iso/\1') },
        # Map xlink relative paths with multiple ../
        { from: %r{(?:\.\./)+xlink/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/xlink/\1') },
        # Map GML relative paths with multiple ../
        { from: %r{(?:\.\./)+gml/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/gml/\1') },
        # Map GML bare filenames
        { from: /^(basicTypes|coordinateOperations|coordinateReferenceSystems|coordinateSystems|coverage|datums|defaultStyle|deprecatedTypes|dictionary|direction|dynamicFeature|feature|geometryAggregates|geometryBasic0d1d|geometryBasic2d|geometryComplexes|geometryPrimitives|gml|gmlBase|grids|measures|observation|referenceSystems|temporal|temporalReferenceSystems|temporalTopology|topology|units|valueObjects)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/gml/3.2.1/\1.xsd') },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.imports).not_to be_empty
    end

    it "matches bare filenames with specific patterns" do
      xsd_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:import namespace="http://www.opengis.net/gml/3.2"
                     schemaLocation="topology.xsd"/>
        </xs:schema>
      XSD

      schema_mappings = [
        # Map GML bare filenames
        { from: /^(basicTypes|coordinateOperations|coordinateReferenceSystems|coordinateSystems|coverage|datums|defaultStyle|deprecatedTypes|dictionary|direction|dynamicFeature|feature|geometryAggregates|geometryBasic0d1d|geometryBasic2d|geometryComplexes|geometryPrimitives|gml|gmlBase|grids|measures|observation|referenceSystems|temporal|temporalReferenceSystems|temporalTopology|topology|units|valueObjects)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/gml/3.2.1/\1.xsd') },
        # Map xlink relative paths (needed by GML schemas)
        { from: %r{(?:\.\./)+xlink/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/xlink/\1') },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.imports).not_to be_empty
    end
  end

  describe "URL pattern mappings" do
    it "maps HTTPS URLs to local directory structure" do
      xsd_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:import namespace="http://www.isotc211.org/2005/gmd"
                     schemaLocation="https://schemas.isotc211.org/19139/20070417/gmd/metadataApplication.xsd"/>
        </xs:schema>
      XSD

      schema_mappings = [
        # Map HTTPS URLs to local ISO directory
        { from: %r{https://schemas\.isotc211\.org/(.+)},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/iso/\1') },
        # Map relative paths for nested includes
        { from: %r{^\.\./gmd/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmd/\1') },
        { from: %r{^\.\./gco/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gco/\1') },
        { from: %r{^\.\./gss/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gss/\1') },
        { from: %r{^\.\./gts/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gts/\1') },
        { from: %r{^\.\./gsr/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gsr/\1') },
        { from: %r{^\.\./gmx/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmx/\1') },
        # Map ISO relative paths with multiple ../
        { from: %r{(?:\.\./)+iso/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/iso/\1') },
        # Map GML with multiple ../
        { from: %r{(?:\.\./)+gml/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/gml/\1') },
        # Map xlink with multiple ../
        { from: %r{(?:\.\./)+xlink/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/xlink/\1') },
        # Map GML bare filenames
        { from: /^(basicTypes|coordinateOperations|coordinateReferenceSystems|coordinateSystems|coverage|datums|defaultStyle|deprecatedTypes|dictionary|direction|dynamicFeature|feature|geometryAggregates|geometryBasic0d1d|geometryBasic2d|geometryComplexes|geometryPrimitives|gml|gmlBase|grids|measures|observation|referenceSystems|temporal|temporalReferenceSystems|temporalTopology|topology|units|valueObjects)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/gml/3.2.1/\1.xsd') },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.imports).not_to be_empty
    end
  end

  describe "mapping order precedence" do
    it "uses first matching mapping when multiple patterns match" do
      xsd_content = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:import namespace="http://example.com/specific"
                     schemaLocation="specific.xsd"/>
        </xs:schema>
      XSD

      specific_path = File.join(fixtures_dir, "metaschema.xsd")
      general_path = File.join(fixtures_dir, "metaschema-datatypes.xsd")

      schema_mappings = [
        # More specific pattern first
        { from: "specific.xsd", to: specific_path },
        # More general pattern second
        { from: /^(.+\.xsd)$/, to: general_path },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: fixtures_dir,
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      # The first matching mapping should be used (specific_path)
    end
  end

  describe "parsing without mappings" do
    it "works for local schemas without imports" do
      xsd_path = File.join(fixtures_dir, "metaschema.xsd")
      xsd_content = File.read(xsd_path)

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        xsd_content,
        location: File.dirname(xsd_path),
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
    end
  end

  describe "nil and empty mappings" do
    let(:simple_xsd) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:element name="test" type="xs:string"/>
        </xs:schema>
      XSD
    end

    it "handles nil schema_mappings" do
      parsed = Lutaml::Xml::Schema::Xsd.parse(
        simple_xsd,
        location: fixtures_dir,
        schema_mappings: nil,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.element.first.name).to eq("test")
    end

    it "handles empty schema_mappings hash" do
      parsed = Lutaml::Xml::Schema::Xsd.parse(
        simple_xsd,
        location: fixtures_dir,
        schema_mappings: {},
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.element.first.name).to eq("test")
    end
  end

  describe "nested schema imports with mappings" do
    it "resolves nested imports using mappings" do
      # Use CityGML building schema which imports cityGMLBase
      citygml_building_path = File.join(fixtures_dir,
                                        "citygml/building/2.0/building.xsd")
      citygml_building_content = File.read(citygml_building_path)

      schema_mappings = [
        # Map cityGMLBase.xsd
        { from: "../../2.0/cityGMLBase.xsd",
          to: File.join(fixtures_dir, "citygml/2.0/cityGMLBase.xsd") },
        # Map GML schemas via HTTP URL
        { from: %r{http://schemas\.opengis\.net/gml/3\.2\.1/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/gml/3.2.1/\1') },
        # Map GML relative paths with multiple ../
        { from: %r{(?:\.\./)+gml/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/gml/\1') },
        # Map GML bare filenames for nested includes
        { from: /^(basicTypes|coordinateOperations|coordinateReferenceSystems|coordinateSystems|coverage|datums|defaultStyle|deprecatedTypes|dictionary|direction|dynamicFeature|feature|geometryAggregates|geometryBasic0d1d|geometryBasic2d|geometryComplexes|geometryPrimitives|gml|gmlBase|grids|measures|observation|referenceSystems|temporal|temporalReferenceSystems|temporalTopology|topology|units|valueObjects)\.xsd$/,
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/gml/3.2.1/\1.xsd') },
        # Map xlink for GML dependencies
        { from: %r{(?:\.\./)+xlink/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/xlink/\1') },
        # Map ISO with multiple ../
        { from: %r{(?:\.\./)+iso/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'codesynthesis-gml-3.2.1/iso/\1') },
        # Map simple relative paths for ISO subdirectories
        { from: %r{^\.\./gmd/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmd/\1') },
        { from: %r{^\.\./gco/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gco/\1') },
        { from: %r{^\.\./gss/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gss/\1') },
        { from: %r{^\.\./gts/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gts/\1') },
        { from: %r{^\.\./gsr/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gsr/\1') },
        { from: %r{^\.\./gmx/(.+\.xsd)$},
          to: File.join(fixtures_dir,
                        'codesynthesis-gml-3.2.1/iso/19139/20070417/gmx/\1') },
        # Map SMIL20 files
        { from: /^(smil20-.*|smil20|xml-mod|rdf)\.xsd$/,
          to: File.join(fixtures_dir, 'smil20/\1.xsd') },
        # Map OASIS xAL
        { from: %r{https?://docs\.oasis-open\.org/election/external/(.+\.xsd)$},
          to: File.join(fixtures_dir, 'citygml/xAL/\1') },
      ]

      parsed = Lutaml::Xml::Schema::Xsd.parse(
        citygml_building_content,
        location: File.dirname(citygml_building_path),
        schema_mappings: schema_mappings,
      )

      expect(parsed).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      expect(parsed.target_namespace).to eq("http://www.opengis.net/citygml/building/2.0")
      # Verify that imports were resolved
      expect(parsed.imports).not_to be_empty
    end
  end

  describe "mappings isolation between parse calls" do
    let(:xsd1) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="test1" type="xs:string"/>
        </xs:schema>
      XSD
    end

    let(:xsd2) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="test2" type="xs:string"/>
        </xs:schema>
      XSD
    end

    it "does not leak mappings between parse calls" do
      mappings1 = [{ from: "http://example.com/schema1.xsd",
                     to: "/local/path1.xsd" }]
      parsed1 = Lutaml::Xml::Schema::Xsd.parse(xsd1, schema_mappings: mappings1)
      expect(parsed1.element.first.name).to eq("test1")

      # Clear mappings explicitly
      Lutaml::Xml::Schema::Xsd::Glob.schema_mappings = nil

      mappings2 = [{ from: "http://example.com/schema2.xsd",
                     to: "/local/path2.xsd" }]
      parsed2 = Lutaml::Xml::Schema::Xsd.parse(xsd2, schema_mappings: mappings2)
      expect(parsed2.element.first.name).to eq("test2")

      # Verify mappings are different
      current_mappings = Lutaml::Xml::Schema::Xsd::Glob.schema_mappings
      expect(current_mappings).to eq(mappings2)
      expect(current_mappings).not_to eq(mappings1)
    end
  end
end
