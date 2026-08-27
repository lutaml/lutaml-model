# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema"
require "bigdecimal"
require "tmpdir"
require "fileutils"

# End-to-end round-trip for issue #191 constraining facets: a constrained type
# survives model -> XSD -> model (its facet macro is regenerated) and an XSD's
# facets survive XSD -> model -> XSD (each facet element reappears).
RSpec.describe "Issue #191 facet round-trip" do
  # Generate XSD from a one-attribute model of the constrained type, compile it
  # back, and return the regenerated source of the facet-bearing ST_* type.
  def round_trip_source(constrained_type)
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :value, constrained_type
      xml do
        root "R"
        map_element "value", to: :value
      end
    end
    xsd = Lutaml::Xml::Schema::XsdSchema.generate(model, pretty: true)
    compiled = Lutaml::Model::Schema::XmlCompiler.to_models(xsd)
    compiled.fetch(compiled.keys.grep(/\AST_/).first)
  end

  describe "model -> XSD -> model regenerates each facet macro" do
    {
      "integer inclusive bounds" => [
        -> { Class.new(Lutaml::Model::Type::Integer) { inclusive min: 0, max: 100 } },
        "inclusive min: 0, max: 100",
      ],
      "integer exclusive bounds" => [
        -> { Class.new(Lutaml::Model::Type::Integer) { exclusive min: 0, max: 100 } },
        "exclusive min: 0, max: 100",
      ],
      "exact length" => [
        -> { Class.new(Lutaml::Model::Type::String) { length 5 } },
        "length 5",
      ],
      "length range" => [
        -> { Class.new(Lutaml::Model::Type::String) { length min: 2, max: 8 } },
        "length min: 2, max: 8",
      ],
      "pattern" => [
        -> { Class.new(Lutaml::Model::Type::String) { pattern(/[A-Z]+/) } },
        "pattern(%r{[A-Z]+})",
      ],
      "enumeration" => [
        -> { Class.new(Lutaml::Model::Type::String) { enumeration("AB", "CD") } },
        'enumeration("AB", "CD")',
      ],
      "whiteSpace" => [
        -> { Class.new(Lutaml::Model::Type::String) { white_space :collapse } },
        "white_space :collapse",
      ],
      "total and fraction digits" => [
        lambda {
          Class.new(Lutaml::Model::Type::Decimal) do
            total_digits 5
            fraction_digits 2
          end
        },
        ["total_digits 5", "fraction_digits 2"],
      ],
      "decimal inclusive bounds" => [
        -> { Class.new(Lutaml::Model::Type::Decimal) { inclusive min: BigDecimal("1.5") } },
        'inclusive min: BigDecimal("1.5")',
      ],
      "float inclusive bounds" => [
        -> { Class.new(Lutaml::Model::Type::Float) { inclusive min: 1.25, max: 9.75 } },
        'inclusive min: Lutaml::Model::Type::Float.cast("1.25")',
      ],
      "date inclusive bound" => [
        lambda {
          Class.new(Lutaml::Model::Type::Date) do
            inclusive min: Lutaml::Model::Type::Date.cast("2020-01-01")
          end
        },
        'inclusive min: Lutaml::Model::Type::Date.cast("2020-01-01")',
      ],
      "boolean enumeration" => [
        -> { Class.new(Lutaml::Model::Type::Boolean) { enumeration(true) } },
        'enumeration(Lutaml::Model::Type::Boolean.cast("true"))',
      ],
    }.each do |facet, (build, macros)|
      it "regenerates #{facet}" do
        source = round_trip_source(build.call)
        Array(macros).each { |macro| expect(source).to include(macro) }
      end
    end

    # Layer-1 attribute facets (issue #191 F3) must also survive the round-trip:
    # `min`/`max` on the attribute emit an xs:restriction that recompiles to the
    # canonical facet macro.
    it "regenerates Layer-1 attribute min/max bounds" do
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :value, :integer, min: 0, max: 100
        xml do
          root "R"
          map_element "value", to: :value
        end
      end
      xsd = Lutaml::Xml::Schema::XsdSchema.generate(model, pretty: true)
      compiled = Lutaml::Model::Schema::XmlCompiler.to_models(xsd)
      source = compiled.fetch(compiled.keys.grep(/\AST_/).first)

      expect(source).to include("inclusive min: 0, max: 100")
    end
  end

  describe "XSD -> model -> XSD regenerates each facet element" do
    let!(:dir) { Dir.mktmpdir }

    let(:regenerated) do
      Lutaml::Model::Schema::XmlCompiler.to_models(
        File.read("spec/fixtures/xml/restriction_facets.xsd"),
        output_dir: dir, create_files: true, module_namespace: "FacetRtSpec",
      )
      require File.join(dir, "facetrtspec_registry.rb")
      FacetRtSpec.register_all
      Lutaml::Xml::Schema::XsdSchema.generate(FacetRtSpec::CTItem, pretty: true)
    end

    after do
      FileUtils.rm_rf(dir)
      # The compiled fixture must load as a real module for register_all; drop it
      # so repeated runs do not accumulate constants.
      # rubocop:disable RSpec/RemoveConst
      Object.send(:remove_const, :FacetRtSpec) if defined?(FacetRtSpec)
      # rubocop:enable RSpec/RemoveConst
    end

    {
      "minLength/maxLength" =>
        ['<minLength value="2"/>', '<maxLength value="8"/>'],
      "min/maxExclusive" =>
        ['<minExclusive value="0"/>', '<maxExclusive value="100"/>'],
      "total/fractionDigits" =>
        ['<totalDigits value="5"/>', '<fractionDigits value="2"/>'],
      "whiteSpace" => ['<whiteSpace value="collapse"/>'],
      "min/maxInclusive" => [
        '<minInclusive value="2020-01-01T00:00:00+00:00"/>',
        '<maxInclusive value="2020-12-31T23:59:59+00:00"/>',
      ],
      "enumeration" => ['<enumeration value="true"/>'],
    }.each do |facet, fragments|
      it "regenerates #{facet}" do
        fragments.each { |fragment| expect(regenerated).to include(fragment) }
      end
    end
  end
end
