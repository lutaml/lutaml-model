# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

ENV["RANTLY_VERBOSE"] ||= "0"
require "rantly"
require "rantly/rspec_extensions"
require "rantly/shrinks"
require "lutaml/lml/format"

# Constants shared by the generative laws (TODO.next/sota/properties.md).
# Seeded and reproducible: the seed is printed before every property run,
# and Rantly shrinks the generated tuple on failure. PR runs use a
# reduced count and depth; the nightly workflow raises both through
# LML_PROPERTY_COUNT / LML_PROPERTY_DEPTH and supplies a fresh seed.
module PropertyLawsSupport
  SEED = Integer(ENV.fetch("LML_PROPERTY_SEED", "20261020"))
  COUNT = Integer(ENV.fetch("LML_PROPERTY_COUNT", "40"))
  DEPTH = Integer(ENV.fetch("LML_PROPERTY_DEPTH", "2"))

  TYPES = {
    string: :string, integer: :integer, float: :float, boolean: :boolean
  }.freeze

  # Values that a bare-word emission would read back as something other
  # than a string (or not read at all).
  EDGE_STRINGS = [
    "", "null", "true", "false", "01", "1.50", "2dCi9o", "0x10",
    "with space", "a-b", 'quote"x', "back\\slash", "  padded  ",
    "line\nbreak", "tab\there", "üñï", "🎨", "12", "-3"
  ].freeze

  STRING_GEN = proc do
    case choose(:print, :ascii, :edge)
    when :print then string(:print)
    when :ascii then string(:ascii)
    else choose(*EDGE_STRINGS)
    end
  end

  # The document-model comparison defined with TODO.canon/5.
  DEFAULT_VALUES = {
    "visibility" => "public", "literal" => false, "is_derived" => false,
    "is_static" => false, "is_read_only" => false, "is_abstract" => false,
    "direction" => "in"
  }.freeze
end

RSpec.describe "LML round-trip properties" do
  def report_seed
    warn "LML property seed: #{PropertyLawsSupport::SEED}"
  end

  def model_class(type)
    Class.new(Lutaml::Model::Serializable) do
      attribute :value, type
      lml { map :value, to: :value }
    end
  end

  def parse(source)
    Lutaml::Lml.parse_document(source)
  end

  def canonical(source)
    Lutaml::Formatter::Canonical.new(parse(source)).render
  rescue Lutaml::Lml::Error => e
    raise "#{e.message}\n--- generated source ---\n#{source}"
  end

  def normalize(node)
    case node
    when Hash
      node.each_with_object({}) do |(key, value), result|
        next if PropertyLawsSupport::DEFAULT_VALUES[key] == value

        if key.to_s.include?("cardinality") && value.is_a?(Hash)
          next if value["min"] == "0" && value["max"] == "1"

          result[key] = value.merge("max" => unbounded(value["max"]))
          next
        end

        result[key] = normalize(value)
      end
    when Array
      node.map { |item| normalize(item) }
    else
      node
    end
  end

  def unbounded(max)
    max == "*" ? "n" : max
  end

  def model(source)
    normalize(parse(source).to_hash)
  end

  describe "L1 value fidelity" do
    it "round-trips generated typed values through to_lml/from_lml" do
      report_seed

      property = property_of do
        kind = choose(:string, :string, :string, :integer, :float, :boolean)
        value = case kind
                when :string then call(PropertyLawsSupport::STRING_GEN)
                when :integer then choose(integer, -618_435_539_813_391_527, 0)
                when :float then choose(float, 1.0e-10, 1.0e20, -1.0e-10)
                else boolean
                end
        Tuple.new([kind, value])
      end

      property.check(PropertyLawsSupport::COUNT) do |pair|
        kind = pair[0]
        value = pair[1]
        klass = model_class(PropertyLawsSupport::TYPES.fetch(kind))
        reloaded = klass.from_lml(klass.new(value: value).to_lml).value

        expect(reloaded).to eq(value), "kind=#{kind} value=#{value.inspect}"
      end
    end
  end

  describe "L2 key fidelity" do
    it "round-trips generated keys and values through the LML adapter" do
      report_seed

      property = property_of do
        Tuple.new([call(PropertyLawsSupport::STRING_GEN),
                   call(PropertyLawsSupport::STRING_GEN)])
      end

      property.check(PropertyLawsSupport::COUNT) do |pair|
        key = pair[0]
        value = pair[1]
        adapter = Lutaml::Lml::Format::Adapter::StandardAdapter
        lml = adapter.new({ "__type__" => "Data", key => value }).to_lml
        hash = adapter.instance_to_hash(parse(lml).instance)

        expect(hash).to include(key => value)
      end
    end
  end

  describe "regressions found by the laws" do
    it "quotes string values that would re-parse as other literals" do
      klass = model_class(:string)

      ["null", "01", "2dCi9o", "0x10", "1.50"].each do |value|
        reloaded = klass.from_lml(klass.new(value: value).to_lml).value

        expect(reloaded).to eq(value), "value=#{value.inspect}"
      end
    end

    it "expands exponent-notation floats into plain decimals" do
      klass = model_class(:float)

      [1.0e-10, 1.0e20, -1.0e-10].each do |value|
        expect(klass.from_lml(klass.new(value: value).to_lml).value).to eq(value)
      end
    end

    it "reads a signed number as a number" do
      reloaded = model_class(:integer)
                 .from_lml("instance Data {\n  value = -618435539813391527\n}").value

      expect(reloaded).to eq(-618_435_539_813_391_527)
    end

    it "keeps a trailing colon on a quoted key" do
      adapter = Lutaml::Lml::Format::Adapter::StandardAdapter
      lml = adapter.new({ "__type__" => "Data", "key:" => "v" }).to_lml
      hash = adapter.instance_to_hash(parse(lml).instance)

      expect(hash).to include("key:" => "v")
    end

    it "renders an exponent float without exponent notation" do
      source = "instance X { a = 0.0000000001 }"
      output = canonical(source)

      expect(output).to include("a = 0.0000000001")
      expect(model(output)).to eq(model(source))
    end
  end

  # ---- grammar-directed document generation ----

  def generated_document(params)
    numbers = params.array
    counts = Array.new(7) { |i| numbers[i] % (PropertyLawsSupport::DEPTH + 1) }
    seed = numbers[7]

    model = []
    model.concat(generated_classes(seed, counts[0]))
    model.concat(generated_enums(seed, counts[1], counts[2]))
    model.concat(generated_packages(seed, counts[3]))
    model.concat(generated_mappings(counts[4]))

    source = +""
    source << "lml \"1.0\"\n\n" if numbers[9].even?
    source << "require \"gen.lml\"\n\n" if numbers[8].even?
    source << wrap_models(seed, model) unless model.empty?
    source << generated_instances(counts[5], counts[6])
    source
  end

  def wrap_models(seed, members)
    "models Gen#{seed % 10} {\n#{indent(members.join("\n\n"))}\n}\n\n"
  end

  def generated_classes(seed, count)
    Array.new(count) do |i|
      attrs = Array.new((seed + i) % (PropertyLawsSupport::DEPTH + 2)) do |j|
        generated_attribute(seed + i + j, j)
      end
      body = attrs.map { |line| indent(line) }
      body << indent("definition \"generated class #{i}\"") if seed.even?
      body << indent("op#{i}(in x: String) : Boolean") if (seed + i) % 4 == 1
      body << indent("** class comment #{i}") if (seed + i) % 4 == 2

      header = "class C#{i}"
      header += " < Base" if (seed + i) % 5 == 3
      "#{header} {\n#{body.join("\n\n")}\n}"
    end
  end

  def generated_attribute(seed, index)
    name = "a#{index}"
    type = PropertyLawsSupport::TYPES.keys.map(&:to_s).map(&:capitalize)[seed % 4]
    case seed % 6
    when 0 then "attribute #{name}, #{type}"
    when 1 then "attribute #{name}, #{type} { cardinality 0..n }"
    when 2 then "attribute #{name}, #{type} { values { \"x\", \"y\" } }"
    when 3 then "attribute #{name}, #{type} { pattern /a[0-9]+/ }"
    when 4 then "-a#{index}: #{type} [1..2]"
    else "attribute #{name}, #{type} { default: \"d#{index}\" }"
    end
  end

  def generated_enums(seed, count, members)
    Array.new(count) do |i|
      body = ["definition \"generated enum #{i}\""]
      Array.new(members) do |m|
        body << generated_enum_member(seed + m, m)
      end
      "enum E#{i} {\n#{indent(body.join("\n\n"))}\n}"
    end
  end

  def generated_enum_member(seed, index)
    case seed % 4
    when 0 then "value \"v#{index}\" {\n  definition \"member #{index}\"\n}"
    when 1 then "value v#{index}"
    when 2 then "m#{index}: String"
    else "value \"p#{index}\" {\n  payload = \"x\"\n  instance Payload {\n    a = \"b\"\n  }\n}"
    end
  end

  def generated_packages(seed, count)
    Array.new(count) do
      "package P#{seed % 10} {\n" \
        "#{indent('class PClass { attribute x, String }')}\n\n" \
        "#{indent('enum PEnum { value "p" }')}\n}"
    end
  end

  def generated_mappings(count)
    return [] if count.zero?

    ["mapping xml Thing {\n" \
     "#{indent('element "thing"')}\n\n" \
     "#{indent('map_element "wire" a0')}\n}"]
  end

  def generated_instances(collections, instances)
    lines = []
    instances.times do |i|
      lines << "instance \"t#{i}\" Thing {"
      lines << indent("a0 = \"value #{i}\"")
      lines << indent("a1 = 1")
      lines << indent("a2 = true")
      lines << indent("a3 = null")
      lines << indent("a4 = [\"x\", \"null\", \"é\"]")
      lines << "}"
    end

    if collections.positive?
      lines << "instances GenInstances {"
      Array.new(collections) do |i|
        lines << indent("collection \"col#{i}\" {")
        lines << indent(indent("includes [\"t#{i}\"]"))
        lines << indent(indent('validation { condition "count >= 0" }'))
        lines << indent("}")
      end
      lines << "}"
    end
    return "" if lines.empty?

    "#{lines.join("\n\n")}\n"
  end

  def indent(text)
    text.lines.map { |line| "  #{line}" }.join
  end

  describe "L3 document semantics" do
    it "preserves generated documents through parse/emit/parse" do
      report_seed

      property = property_of do
        Tuple.new(Array.new(10) { range(0, 24) })
      end

      property.check(PropertyLawsSupport::COUNT) do |params|
        source = generated_document(params)

        expect(model(canonical(source))).to eq(model(source)), "source:\n#{source}"
      end
    end
  end

  describe "L4 idempotence" do
    it "renders generated documents to a fixed point" do
      report_seed

      property = property_of do
        Tuple.new(Array.new(10) { range(0, 24) })
      end

      property.check(PropertyLawsSupport::COUNT) do |params|
        source = generated_document(params)
        once = canonical(source)

        expect(canonical(once)).to eq(once), "source:\n#{source}"
      end
    end
  end
end
