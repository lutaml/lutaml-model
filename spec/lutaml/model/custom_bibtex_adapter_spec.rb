# = BibTeX Support in Lutaml::Model
#
# This extension adds support for BibTeX format serialization and deserialization
# to Lutaml::Model. While BibTeX is traditionally used for academic citations,
# its structured format makes it suitable for storing various types of information models.
#
# == Key Benefits of BibTeX Format
#
# - Built-in support for structured data with fields and values
# - Natural handling of collections (like authors, dependencies, ingredients)
# - Familiar citation key system for unique identification
# - Human-readable text format for easy version control
# - Extensive tooling support for parsing and manipulation
#
# == Basic Setup
#
# To use BibTeX format in your model:
#
# 1. Include necessary field classes based on your needs:
#    - BibtexFieldAuthor - For handling names (authors, maintainers, manufacturers)
#    - BibtexFieldYear - For handling dates and ranges
#    - BibtexFieldPage - For handling numeric ranges
#
# 2. Define your model class inheriting from Lutaml::Model::Serializable
#
# 3. Register BibTeX format:
#
#    Lutaml::Model::Config.register_format(
#      :bibtex,
#      mapping_class: BibtexMapping,
#      adapter_class: BibtexAdapter
#    )
#
# 4. Define BibTeX mappings using the `bibtex do` block:
#
#    bibtex do
#      map_entry_type to: :entry_type     # Maps entry type (e.g., @article, @book)
#      map_citekey to: :citekey           # Maps unique identifier
#      map_field "author", to: :author    # Maps fields to model attributes
#      map_field "title", to: :title
#      # Add other field mappings as needed
#    end
#
# == Mapping Methods
#
# The bibtex block supports these mapping methods:
#
# - map_entry_type: Maps the entry type (e.g., @article, @book)
# - map_citekey: Maps the unique identifier
# - map_field: Maps fields to model attributes
#   Options:
#   - to: Target attribute name
#   - render_nil: Whether to render nil values (default: false)
#
# == Examples
#
# === 1. Traditional Academic Citation
#
#   class Publication < Lutaml::Model::Serializable
#     attribute :entry_type, :string, values: %w[article book inproceedings]
#     attribute :citekey, :string
#     attribute :author, BibtexFieldAuthor
#     attribute :title, :string
#     attribute :journal, :string
#     attribute :year, BibtexFieldYear
#
#     bibtex do
#       map_entry_type to: :entry_type
#       map_citekey to: :citekey
#       map_field "author", to: :author
#       map_field "title", to: :title
#       map_field "journal", to: :journal
#       map_field "year", to: :year
#     end
#   end
#
# Usage:
#   entry = Publication.from_bibtex(bibtex_string)
#   bibtex_string = entry.to_bibtex
#
# === 2. Software Components Registry
#
# BibTeX's structured format works well for tracking software components:
#
#   class Component < Lutaml::Model::Serializable
#     attribute :entry_type, :string, values: %w[library framework tool service]
#     attribute :citekey, :string  # Unique identifier
#     attribute :name, :string
#     attribute :maintainers, BibtexFieldAuthor, collection: true
#     attribute :version, :string
#     attribute :dependencies, :string, collection: true
#     attribute :license, :string
#
#     bibtex do
#       map_entry_type to: :entry_type
#       map_citekey to: :citekey
#       map_field "name", to: :name
#       map_field "maintainers", to: :maintainers
#       map_field "version", to: :version
#       map_field "dependencies", to: :dependencies
#       map_field "license", to: :license
#     end
#   end
#
# === 3. Equipment Inventory
#
#   class Equipment < Lutaml::Model::Serializable
#     attribute :entry_type, :string, values: %w[machine tool vehicle equipment]
#     attribute :citekey, :string  # Asset ID
#     attribute :model, :string
#     attribute :manufacturer, BibtexFieldAuthor
#     attribute :purchase_date, BibtexFieldYear
#     attribute :location, :string
#     attribute :maintenance_history, :string, collection: true
#
#     bibtex do
#       map_entry_type to: :entry_type
#       map_citekey to: :citekey
#       map_field "model", to: :model
#       map_field "manufacturer", to: :manufacturer
#       map_field "purchase_date", to: :purchase_date
#       map_field "location", to: :location
#       map_field "maintenance_history", to: :maintenance_history
#     end
#   end
#
# === 4. Recipe Database
#
#   class Recipe < Lutaml::Model::Serializable
#     attribute :entry_type, :string, values: %w[appetizer main dessert beverage]
#     attribute :citekey, :string  # Recipe ID
#     attribute :name, :string
#     attribute :chef, BibtexFieldAuthor
#     attribute :prep_time, :string
#     attribute :ingredients, :string, collection: true
#     attribute :instructions, :string, collection: true
#     attribute :servings, :string
#
#     bibtex do
#       map_entry_type to: :entry_type
#       map_citekey to: :citekey
#       map_field "name", to: :name
#       map_field "chef", to: :chef
#       map_field "prep_time", to: :prep_time
#       map_field "ingredients", to: :ingredients
#       map_field "instructions", to: :instructions
#       map_field "servings", to: :servings
#     end
#   end
#
require "spec_helper"
require_relative "../../../lib/lutaml/model/serialization_adapter"

# This is a custom BibTeX adapter that can serialize and deserialize BibTeX
# entries. It is used to demonstrate how to create a custom adapter for a
# specific format.
#

module CustomBibtexAdapterSpec
  class BibtexDocument; end

  class BibtexAdapter < Lutaml::Model::SerializationAdapter
    handles_format :bibtex
    document_class BibtexDocument

    def initialize(document)
      @document = document
    end

    def to_bibtex(*)
      @document.to_bibtex
    end
  end

  class BibtexDocument
    attr_reader :attributes

    def initialize(attributes = {}, options = {})
      @attributes = attributes
      @mapping = options.delete(:mapping)
    end

    def [](key)
      @attributes[key]
    end

    def []=(key, value)
      @attributes[key] = value
    end

    def to_h
      @attributes
    end

    def self.parse(bibtex_data, options = {})
      mapping = options.delete(:mapping)
      entries = bibtex_data.scan(/@(\w+)\s*{\s*([\w-]+),\s*((?:\s*\w+\s*=\s*\{.*?\},?\s*)+)\s*}/).map do |type, key, fields|
        [type, BibtexDocumentEntry.parse(type, key, fields, mapping)]
      end.to_h

      new(entries)
    end

    def to_bibtex(*)
      @attributes.map do |entry|
        entry.to_bibtex
      end.join("\n")
    end
  end

  class BibtexDocumentEntry
    attr_reader :entry_type, :citekey, :fields, :mapping

    def initialize(entry_type:, citekey:, fields:, mapping: nil)
      @entry_type = entry_type
      @citekey = citekey
      @fields = fields

      if @fields["author"].is_a?(Array)
        @fields["author"] = @fields["author"].map { |a| a.gsub(/\s*,\s*/, ", ") }.join(" and ")
      end
      @mapping = mapping
    end

    def self.parse(type, key, fields, mapping)
      fields_hash = fields.scan(/(\w+)\s*=\s*[{"](.+?)[}"]/m).to_h
      new(
        entry_type: type.downcase,
        citekey: key.strip,
        fields: fields_hash.transform_keys(&:downcase),
        mapping: mapping,
      )
    end

    def to_bibtex(*)
      <<~BIBTEX
        @#{entry_type}{#{citekey},
          #{fields.compact.map { |k, v| "#{k} = {#{v}}" }.join(",\n  ")}
        }
      BIBTEX
    end
  end

  class BibtexMappingRule < Lutaml::Model::MappingRule
    # Can be :entry_type, :citekey, or :field
    attr_reader :field_type

    def initialize(
      name,
      to:,
      render_nil: false,
      render_default: false,
      with: {},
      delegate: nil,
      field_type: :field,
      transform: {}
    )
      super(name, to: to, render_nil: render_nil, render_default: render_default,
                  with: with, delegate: delegate, transform: transform)
      @field_type = field_type
    end

    def entry_type?
      field_type == :entry_type
    end

    def citekey?
      field_type == :citekey
    end

    def deep_dup
      self.class.new(
        name.dup,
        to: to.dup,
        render_nil: render_nil.dup,
        with: Utils.deep_dup(custom_methods),
        delegate: delegate,
        field_type: field_type,
        transform: Utils.deep_dup(transform),
      )
    end
  end

  class BibtexMapping < Lutaml::Model::Mapping
    attr_reader :mappings

    def initialize
      super
      @mappings = []
    end

    def map_entry_type(to:)
      add_mapping("__entry_type", to, field_type: :entry_type)
    end

    def map_citekey(to:)
      add_mapping("__citekey", to, field_type: :citekey)
    end

    def map_field(name, to:, render_nil: false)
      add_mapping(name, to, field_type: :field, render_nil: render_nil)
    end

    def add_mapping(name, to, **options)
      # validate!(name, to, {})
      @mappings << BibtexMappingRule.new(name, to: to, **options)
    end

    def mapping_for_field(field)
      @mappings.find { |m| m.field_type == field }
    end

    def validate_mapping
      entry_type = @mappings.find { |m| m.field_type == :entry_type }
      raise "Entry type mapping is required" unless entry_type

      cite_key = @mappings.find { |m| m.field_type == :citekey }
      raise "Cite key mapping is required" unless cite_key
    end
  end

  class BibtexTransform < Lutaml::Model::Transform
    def self.data_to_model(context, data, _format, _options = {})
      new(context).data_to_model(data)
    end

    def self.model_to_data(context, model, _format, _options = {})
      new(context).model_to_data(model)
    end

    # Assume we have a method `model_class` set at the Lutaml::Model::Mapping level
    def data_to_model(data) # a BibtexDocumentEntry object
      mappings = context.mappings_for(:bibtex)

      data.attributes.map do |type, entry|
        bibtex_entry = model_class.new

        mappings.mappings.map do |mapping|
          attribute = attributes[mapping.to]
          field_value = if mapping.entry_type?
                          entry.entry_type
                        elsif mapping.citekey?
                          entry.citekey
                        else
                          entry.fields[mapping.name]
                        end

          if field_value
            bibtex_entry.public_send(
              :"#{mapping.to}=",
              attribute.type.from_bibtex(field_value),
            )
          end
        end

        bibtex_entry
      end
    end

    def model_to_data(model) # a BibtexEntry object
      entry_type = model.entry_type
      citekey = model.citekey
      mapping = context.mappings_for(:bibtex)

      fields = mapping.mappings.each_with_object({}) do |m, acc|
        next if %i[entry_type citekey].include?(m.field_type)

        attribute = attributes[m.to]

        acc[m.name] = if attribute.collection?
                        model.send(m.to).map(&:to_bibtex)
                      elsif model.send(m.to).respond_to?(:to_bibtex)
                        model.send(m.to).to_bibtex
                      else
                        model.send(m.to)
                      end
      end

      BibtexDocumentEntry.new(
        entry_type: entry_type,
        citekey: citekey,
        fields: fields,
      )
    end
  end

  # Define BibTeX field classes
  class BibtexFieldPage < Lutaml::Model::Serializable
    attribute :first, :string
    attribute :last, :string

    def self.from_bibtex(value)
      if value.include?("--")
        first, last = value.split("--")
        BibtexFieldPage.new(first: first, last: last)
      else
        BibtexFieldPage.new(first: value)
      end
    end

    def to_bibtex
      first && last ? "#{first}--#{last}" : (first || last || "")
    end
  end

  class BibtexFieldAuthor < Lutaml::Model::Serializable
    attribute :given, :string    # First name
    attribute :family, :string   # Last name
    attribute :particle, :string # Particle (von, van, de, etc.)
    attribute :suffix, :string   # Suffix (Jr., III, etc.)

    def self.from_bibtex(value)
      parts = value.split(/\s+and\s+/)
      parts.map do |part|
        given, family = part.split(/\s*,\s*/)
        particle, family = family.split(/\s+/) if family&.include?(" ")
        suffix = family.split(/\s+/).last if family&.include?(" ")
        BibtexFieldAuthor.new(given: given, family: family, particle: particle, suffix: suffix)
      end
    end

    def to_bibtex
      [
        particle,
        family,
        ",",
        suffix,
        given,
      ].compact.join(" ")
    end
  end

  class BibtexFieldAuthorCollection < Lutaml::Model::Serializable
    attribute :authors, BibtexFieldAuthor, collection: true

    # BibTeX uses "and" to separate authors
    def self.from_bibtex(value)
      authors = value.split(/\s+and\s+/)

      authors = authors.map do |author|
        BibtexFieldAuthor.from_bibtex(author)
      end

      new(authors: authors)
    end

    def to_bibtex
      authors.map(&:to_bibtex).join(" and ")
    end
  end

  class BibtexFieldYear < Lutaml::Model::Serializable
    attribute :from, :string
    attribute :to, :string

    def self.from_bibtex(value)
      # If the year is a range, split it into from and to parts
      # Otherwise, set the from part and leave the to part empty
      # BibtexFieldYear.
      if value.include?("--")
        from, to = value.split("--")
        BibtexFieldYear.new(from: from, to: to)
      else
        BibtexFieldYear.new(from: value)
      end
    end

    def to_bibtex
      from && to ? "#{from}--#{to}" : (from || to || "")
    end
  end

  # Register BibTeX format
  Lutaml::Model::FormatRegistry.register(
    :bibtex,
    mapping_class: BibtexMapping,
    adapter_class: BibtexAdapter,
    transformer: BibtexTransform,
  )

  # Define BibTeX entry class
  class BibtexEntry < Lutaml::Model::Serializable
    attribute :entry_type, :string, values: %w[
      article book inproceedings conference phdthesis
      mastersthesis techreport manual misc
    ]
    attribute :citekey, :string
    attribute :author, BibtexFieldAuthor, collection: true
    attribute :title, :string
    attribute :journal, :string
    attribute :year, BibtexFieldYear
    attribute :volume, :string
    attribute :number, :string
    attribute :publisher, :string
    attribute :address, :string
    attribute :url, :string
    attribute :pages, BibtexFieldPage

    # Define BibTeX mappings
    bibtex do
      map_entry_type to: :entry_type
      map_citekey to: :citekey
      map_field "author", to: :author
      map_field "title", to: :title
      map_field "journal", to: :journal
      map_field "year", to: :year
      map_field "volume", to: :volume
      map_field "number", to: :number, render_nil: true
      map_field "pages", to: :pages
      map_field "publisher", to: :publisher
      map_field "address", to: :address
      map_field "url", to: :url
    end
  end
end

RSpec.describe "Custom BibTeX adapter" do
  let(:article) do
    CustomBibtexAdapterSpec::BibtexEntry.new(
      entry_type: "book",
      citekey: "schenck1997",
      title: "The EXPRESS way",
      author: [
        CustomBibtexAdapterSpec::BibtexFieldAuthor.new(given: "Doug", family: "Schenck"),
        CustomBibtexAdapterSpec::BibtexFieldAuthor.new(given: "Peter", family: "Wilson"),
      ],
      year: CustomBibtexAdapterSpec::BibtexFieldYear.new(from: "1997"),
      publisher: "Addison-Wesley",
      address: "Reading, Massachusetts",
      pages: "1--100",
    )
  end

  let(:bibtex_string) do
    <<~BIBTEX
      @book{schenck1997,
        author = {Schenck, Doug and Wilson, Peter},
        title = {The EXPRESS way},
        year = {1997},
        pages = {1--100},
        publisher = {Addison-Wesley},
        address = {Reading, Massachusetts}
      }
    BIBTEX
  end

  describe "#to_bibtex" do
    it "serializes to BibTeX format" do
      expect(article.to_bibtex.gsub(/\s+/, " ").strip).to eq(
        bibtex_string.gsub(/\s+/, " ").strip,
      )
    end
  end

  describe ".from_bibtex" do
    let(:bibtex_string) do
      <<~BIBTEX
        @book{schenck1997,
          title = {The EXPRESS way},
          author = {Doug, Schenck and Peter, Wilson},
          year = {1997},
          publisher = {Addison-Wesley},
          address = {Reading, Massachusetts},
          pages = {1--100}
        }

        @misc{iso10303-11,
          author = {ISO/TC 184/SC 4},
          title = {Industrial automation systems and integration -- Product data representation and exchange -- Part 11: Description methods: The EXPRESS language reference manual},
          year = {2004},
          url = {https://www.iso.org/standard/38051.html},
          publisher = {ISO},
          address = {Geneva, Switzerland}
        }
      BIBTEX
    end

    it "deserializes from BibTeX format" do
      result = CustomBibtexAdapterSpec::BibtexEntry.from_bibtex(bibtex_string)

      expect(result.size).to eq(2)

      result[0].tap do |book|
        expect(book.entry_type).to eq("book")
        expect(book.citekey).to eq("schenck1997")
        expect(book.title).to eq("The EXPRESS way")
        expect(book.author.size).to eq(2)
        expect(book.author[0].given).to eq("Doug")
        expect(book.author[0].family).to eq("Schenck")
        expect(book.author[1].given).to eq("Peter")
        expect(book.author[1].family).to eq("Wilson")
        expect(book.year.from).to eq("1997")
        expect(book.publisher).to eq("Addison-Wesley")
        expect(book.address).to eq("Reading, Massachusetts")
      end

      result[1].tap do |misc|
        expect(misc.entry_type).to eq("misc")
        expect(misc.citekey).to eq("iso10303-11")
        expect(misc.title).to eq("Industrial automation systems and integration -- Product data representation and exchange -- Part 11: Description methods: The EXPRESS language reference manual")
        expect(misc.author.size).to eq(1)
        expect(misc.author[0].given).to eq("ISO/TC 184/SC 4")
        expect(misc.year.from).to eq("2004")
        expect(misc.url).to eq("https://www.iso.org/standard/38051.html")
        expect(misc.publisher).to eq("ISO")
        expect(misc.address).to eq("Geneva, Switzerland")
      end
    end
  end
end
