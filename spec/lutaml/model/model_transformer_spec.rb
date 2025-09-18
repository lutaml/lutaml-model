# frozen_string_literal: true

require "spec_helper"
require "date"
require_relative "../../../lib/lutaml/model/model_transformer"

class ProcValue < Lutaml::Model::Serializable
  attribute :val, :string
end

class ProcValueTransformed < Lutaml::Model::Serializable
  attribute :val, :string
end

class ProcMappingTransform < Lutaml::Model::ModelTransformer
  source ProcValue
  target ProcValueTransformed

  transform do
    map from: "val", to: "val", transform: lambda(&:reverse), reverse_transform: lambda(&:reverse)
  end
end

class Author < Lutaml::Model::Serializable
  attribute :name, :string
end

class Address < Lutaml::Model::Serializable
  attribute :street, :string
  attribute :city, :string
end

class PersonWithAddress < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :address, Address
end

class Location < Lutaml::Model::Serializable
  attribute :road, :string
  attribute :town, :string
end

class UserWithLocation < Lutaml::Model::Serializable
  attribute :full_name, :string
  attribute :location, Location
end

# Nested mapping transformer
class PersonLocationTransform < Lutaml::Model::ModelTransformer
  source PersonWithAddress
  target UserWithLocation

  transform do
    map from: "name", to: "full_name"
    map from: "address", to: "location" do
      map from: "street", to: "road"
      map from: "city", to: "town"
    end
  end
end

class Publication < Lutaml::Model::Serializable
  attribute :title, :string
  attribute :author, :string
  attribute :birth_date, :string
  attribute :year_born, :string
  attribute :authors, Author, collection: true
end

class CatalogEntry < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :creator, :string
  attribute :date, :string
  attribute :author, :string
  attribute :birth_year, :string
  attribute :contributors, Author, collection: true
end

class Person < Lutaml::Model::Serializable
  attribute :year_born, :string
  attribute :birth_date, :string
end

class User < Lutaml::Model::Serializable
  attribute :birth_year, :string
  attribute :birth_date, :date
end

class Contributor < Lutaml::Model::Serializable
  attribute :name, :string
end

class UnstructuredDateTime < Lutaml::Model::Serializable
  attribute :value, :string
end

class StructuredDateTime < Lutaml::Model::Serializable
  attribute :date, :string
  attribute :time, :string
end

class OldDigitalTimepiece < Lutaml::Model::Serializable
  attribute :raw_time, UnstructuredDateTime
end

class NewDigitalTimepiece < Lutaml::Model::Serializable
  attribute :detailed_time, StructuredDateTime
end

# Test helper classes for error/edge-case scenarios
class RandomSource
  DUMMY = true
end

class RandomTarget
  DUMMY = true
end

class BadDeclaration < Lutaml::Model::ModelTransformer
  source RandomSource
  target RandomTarget

  def self.try_declare
    transform do
      :ok
    end
  end
end

class ReverseDeclare < Lutaml::Model::ModelTransformer
  source Person
  target User

  def self.try_declare
    reverse_transform do
      :ok
    end
  end
end

class NoForwardValueTransform < Lutaml::Model::ModelTransformer
  source :string
  target :date
end

class InvalidMapTo < Lutaml::Model::ModelTransformer
  source Person
  target User

  def self.build
    transform do
      map from: "name", to: "unknown"
    end
  end
end

class DateTimeSplitTransform < Lutaml::Model::ModelTransformer
  source UnstructuredDateTime
  target StructuredDateTime

  transform do |src|
    date, time = (src.value || "").split("T", 2)
    StructuredDateTime.new(date: date, time: time)
  end

  reverse_transform do |dst|
    UnstructuredDateTime.new(value: [dst.date, dst.time].join("T"))
  end
end

class TimepieceTransform < Lutaml::Model::ModelTransformer
  source OldDigitalTimepiece
  target NewDigitalTimepiece

  transform do
    map from: "raw_time", to: "detailed_time", transform: DateTimeSplitTransform
  end
end

class UniOnlyStringToDate < Lutaml::Model::ModelTransformer
  source :string
  target :date

  transform do |val|
    Date.parse(val)
  end
end

class OneWayModelTransform < Lutaml::Model::ModelTransformer
  source Person
  target User

  transform do
    map from: "birth_date", to: "birth_date", transform: UniOnlyStringToDate
  end
end

# Value transform examples
class DateFormatTransform < Lutaml::Model::ModelTransformer
  source :string
  target :date

  transform do |val|
    Date.parse(val)
  end

  reverse_transform do |val|
    val.strftime("%Y-%m-%d")
  end
end

# Model transform examples
class PublicationTransform < Lutaml::Model::ModelTransformer
  source Publication
  target CatalogEntry

  transform do
    map from: "title", to: "name"
    map from: "author", to: "creator"
  end
end

class UserTransform < Lutaml::Model::ModelTransformer
  source Person
  target User

  transform do
    map from: "year_born", to: "birth_year"
    map from: "birth_date", to: "birth_date", transform: DateFormatTransform
  end
end

class AuthorTransform < Lutaml::Model::ModelTransformer
  source Author
  target Contributor

  transform do
    map from: "name", to: "name"
  end
end

class PublicationCollectionTransform < Lutaml::Model::ModelTransformer
  source Publication
  target CatalogEntry

  transform do
    map_each from: "authors", to: "contributors", transform: AuthorTransform
  end
end

# Clean, unified models
class SimpleString < Lutaml::Model::Serializable
  attribute :value, :string
end

class SimpleDate < Lutaml::Model::Serializable
  attribute :value, :date
end

class Person < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :year_born, :string
  attribute :birth_date, :string
  attribute :address, :string
end

class User < Lutaml::Model::Serializable
  attribute :full_name, :string
  attribute :birth_year, :string
  attribute :birth_date, :date
  attribute :location, :string
end

class Author < Lutaml::Model::Serializable
  attribute :name, :string
end

class Contributor < Lutaml::Model::Serializable
  attribute :name, :string
end

class Publication < Lutaml::Model::Serializable
  attribute :title, :string
  attribute :author, :string
  attribute :authors, Author, collection: true
end

class CatalogEntry < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :creator, :string
  attribute :contributors, Contributor, collection: true
end

# Value transform
class StringToDateTransform < Lutaml::Model::ModelTransformer
  source :string
  target :date

  transform do |val|
    Date.parse(val)
  end

  reverse_transform do |val|
    val.strftime("%Y-%m-%d")
  end
end

# Model to model mapping
class PersonUserTransform < Lutaml::Model::ModelTransformer
  source Person
  target User

  transform do
    map from: "name", to: "full_name"
    map from: "year_born", to: "birth_year"
    map from: "birth_date", to: "birth_date", transform: StringToDateTransform
    map from: "address", to: "location"
  end
end

# Collection mapping
class AuthorContributorTransform < Lutaml::Model::ModelTransformer
  source Author
  target Contributor

  transform do
    map from: "name", to: "name"
  end
end

class PublicationCatalogTransform < Lutaml::Model::ModelTransformer
  source Publication
  target CatalogEntry

  transform do
    map from: "title", to: "name"
    map from: "author", to: "creator"
    map_each from: "authors", to: "contributors", transform: AuthorContributorTransform
  end
end

# Value <-> Model
class StringToPersonTransform < Lutaml::Model::ModelTransformer
  source :string
  target Person

  transform do |input|
    parts = input.split(",")
    Person.new(name: parts[0], year_born: parts[1], birth_date: parts[2], address: parts[3])
  end

  reverse_transform do |person|
    [person.name, person.year_born, person.birth_date, person.address].join(",")
  end
end

class MethodTransform < Lutaml::Model::ModelTransformer
  source Person
  target User

  def upcase_name(value)
    value&.upcase
  end

  def downcase_name(value)
    value&.downcase
  end

  transform do
    map from: "name", to: "full_name", transform: :upcase_name, reverse_transform: :downcase_name
  end
end

class Tag < Lutaml::Model::Serializable
  attribute :name, :string
end

class WithTagsString < Lutaml::Model::Serializable
  attribute :tags_str, :string
end

class WithTagsCollection < Lutaml::Model::Serializable
  attribute :tags, Tag, collection: true
end

class TagsSplitTransform < Lutaml::Model::ModelTransformer
  source :string
  target Tag

  transform do |str|
    (str || "").split(",").map { |t| Tag.new(name: t.strip) }.reject { |t| t.name.empty? }
  end
end

class TagsMapping < Lutaml::Model::ModelTransformer
  source WithTagsString
  target WithTagsCollection

  transform do
    map from: "tags_str", to: "tags", transform: TagsSplitTransform
  end
end

class InvalidMap < Lutaml::Model::ModelTransformer
  source Person
  target User

  def self.build
    transform do
      map from: "unknown", to: "full_name"
    end
  end
end

class DuplicateMap < Lutaml::Model::ModelTransformer
  source Person
  target User

  def self.build
    transform do
      map from: "name", to: "full_name"
      map from: "name", to: "full_name"
    end
  end
end

RSpec.describe Lutaml::Model::ModelTransformer do
  it "transforms string to date and back" do
    expect(StringToDateTransform.transform("2025-03-15")).to eq(Date.new(2025, 3, 15))
    expect(StringToDateTransform.reverse_transform(Date.new(2025, 3, 15))).to eq("2025-03-15")
  end

  it "transforms person to user and back" do
    person = Person.new(name: "Alice", year_born: "1980", birth_date: "2021-01-01", address: "Main St")
    user = PersonUserTransform.transform(person)
    expect(user.full_name).to eq("Alice")
    expect(user.birth_year).to eq("1980")
    expect(user.birth_date).to eq(Date.new(2021, 1, 1))
    expect(user.location).to eq("Main St")
    # Reverse
    person2 = PersonUserTransform.reverse_transform(user)
    expect(person2.name).to eq("Alice")
    expect(person2.year_born).to eq("1980")
    expect(person2.birth_date).to eq("2021-01-01")
    expect(person2.address).to eq("Main St")
  end

  it "transforms publication to catalog entry and back (collections)" do
    pub = Publication.new(title: "Book", author: "Author", authors: [Author.new(name: "A"), Author.new(name: "B")])
    cat = PublicationCatalogTransform.transform(pub)
    expect(cat.name).to eq("Book")
    expect(cat.creator).to eq("Author")
    expect(cat.contributors.map(&:name)).to eq(["A", "B"])
    # Reverse
    pub2 = PublicationCatalogTransform.reverse_transform(cat)
    expect(pub2.title).to eq("Book")
    expect(pub2.author).to eq("Author")
    expect(pub2.authors.map(&:name)).to eq(["A", "B"])
  end

  it "transforms string to person and back (value <-> model)" do
    str = "Bob,1970,2000-01-01,Elm St"
    person = StringToPersonTransform.transform(str)
    expect(person.name).to eq("Bob")
    expect(person.year_born).to eq("1970")
    expect(person.birth_date).to eq("2000-01-01")
    expect(person.address).to eq("Elm St")
    # Reverse
    expect(StringToPersonTransform.reverse_transform(person)).to eq(str)
  end

  describe "Proc-based mapping transforms" do
    let(:simple) { ProcValue.new(val: "hello") }

    it "maps with proc-based value transformation" do
      transformed = ProcMappingTransform.transform(simple)
      expect(transformed.val).to eq("olleh")
    end

    it "reverse maps with proc-based value transformation" do
      transformed = ProcValueTransformed.new(val: "olleh")
      original = ProcMappingTransform.reverse_transform(transformed)
      expect(original.val).to eq("hello")
    end
  end

  describe "Nested model-to-model transforms" do
    let(:person) { PersonWithAddress.new(name: "Alice", address: Address.new(street: "Main St", city: "Metropolis")) }

    it "maps nested attributes between models" do
      user = PersonLocationTransform.transform(person)
      expect(user.full_name).to eq("Alice")
      expect(user.location.road).to eq("Main St")
      expect(user.location.town).to eq("Metropolis")

      # Reverse
      person2 = PersonLocationTransform.reverse_transform(user)
      expect(person2.name).to eq("Alice")
      expect(person2.address.street).to eq("Main St")
      expect(person2.address.city).to eq("Metropolis")
    end
  end

  describe "Value transforms" do
    it "transforms string to date and back" do
      date_str = "2021-01-01"
      date_obj = DateFormatTransform.transform(date_str)
      expect(date_obj).to eq(Date.new(2021, 1, 1))
      expect(DateFormatTransform.reverse_transform(date_obj)).to eq("2021-01-01")
    end
  end

  describe "Model transforms" do
    let(:person) { Person.new(year_born: "1980", birth_date: "2021-01-01") }

    it "maps attributes with identical names" do
      pub = Publication.new(title: "The Art of War", author: "Sun Tzu")
      transformed = PublicationTransform.transform(pub)
      expect(transformed.name).to eq("The Art of War")
      expect(transformed.creator).to eq("Sun Tzu")
      # Reverse
      pub2 = PublicationTransform.reverse_transform(transformed)
      expect(pub2.title).to eq("The Art of War")
      expect(pub2.author).to eq("Sun Tzu")
    end

    it "renames attributes" do
      user = UserTransform.transform(person)
      expect(user.birth_year).to eq("1980")
      # Reverse
      person2 = UserTransform.reverse_transform(user)
      expect(person2.year_born).to eq("1980")
    end

    it "maps with value transformation" do
      user = UserTransform.transform(person)
      expect(user.birth_date).to eq(Date.new(2021, 1, 1))
      # Reverse
      person2 = UserTransform.reverse_transform(user)
      expect(person2.birth_date).to eq("2021-01-01")
    end
  end

  describe "Collection transforms" do
    it "maps collections using map_each" do
      pub = Publication.new(authors: [Author.new(name: "A"), Author.new(name: "B")])
      cat = PublicationCollectionTransform.transform(pub)
      expect(cat.contributors.map(&:name)).to eq(["A", "B"])
      # Reverse
      pub2 = PublicationCollectionTransform.reverse_transform(cat)
      expect(pub2.authors.map(&:name)).to eq(["A", "B"])
    end
  end

  describe "Validation errors" do
    it "raises when mapping refers to unknown attributes" do
      expect { InvalidMap.build }.to raise_error(Lutaml::Model::MappingAttributeMissingError, /Mapping 'from' is required/)
    end

    it "raises when duplicate mapping is declared" do
      expect { DuplicateMap.build }.to raise_error(Lutaml::Model::MappingAlreadyExistsError, /Mapping already exists/)
    end
  end

  describe "Symbol method transforms" do
    it "invokes instance methods for transform and reverse_transform" do
      p = Person.new(name: "Alice")
      u = MethodTransform.transform(p)
      expect(u.full_name).to eq("ALICE")
      p2 = MethodTransform.reverse_transform(u)
      expect(p2.name).to eq("alice")
    end
  end

  describe "Forward-only splitting into a collection" do
    it "splits a delimited string into a collection of models" do
      src = WithTagsString.new(tags_str: "a, b, c")
      dst = TagsMapping.transform(src)
      expect(dst.tags.map(&:name)).to eq(%w[a b c])
    end
  end

  describe "Nil propagation in nested mappings" do
    it "propagates nil nested sources to nil targets" do
      person = PersonWithAddress.new(name: "Alice", address: nil)
      user = PersonLocationTransform.transform(person)
      expect(user.full_name).to eq("Alice")
      expect(user.location).to be_nil

      # Reverse where nested target is nil
      user2 = UserWithLocation.new(full_name: "Bob", location: nil)
      person2 = PersonLocationTransform.reverse_transform(user2)
      expect(person2.name).to eq("Bob")
      expect(person2.address).to be_nil
    end
  end

  describe "Value transformer without reverse" do
    it "raises when reverse_transform is not defined" do
      expect { UniOnlyStringToDate.reverse_transform(Date.today) }.to raise_error(Lutaml::Model::ReverseTransformBlockNotDefinedError)
    end
  end

  describe "Error declarations and edge cases" do
    it "raises UnknownTransformationTypeError for unsupported source/target classes" do
      expect { BadDeclaration.try_declare }.to raise_error(Lutaml::Model::UnknownTransformationTypeError)
    end

    it "raises ReverseTransformationDeclarationError when declaring reverse_transform for model-to-model" do
      expect { ReverseDeclare.try_declare }.to raise_error(Lutaml::Model::ReverseTransformationDeclarationError)
    end

    it "raises TransformBlockNotDefinedError when forward value transform block missing" do
      expect { NoForwardValueTransform.transform("2021-01-01") }.to raise_error(Lutaml::Model::TransformBlockNotDefinedError)
    end

    it "raises MappingAttributeMissingError when 'to' attribute is unknown" do
      expect { InvalidMapTo.build }.to raise_error(Lutaml::Model::MappingAttributeMissingError, /Mapping 'to' is required/)
    end

    it "propagates nil for map_each when source collection is nil" do
      pub = Publication.new(title: "Book", author: "Author", authors: nil)

      cat = PublicationCollectionTransform.transform(pub)
      expect(cat.contributors).to be_nil
    end

    it "passes through empty arrays for map_each" do
      pub = Publication.new(title: "Book", author: "Author", authors: [])

      cat = PublicationCollectionTransform.transform(pub)
      expect(cat.contributors).to eq([])
    end

    it "supports cross model-value nested transform (forward and reverse)" do
      src = OldDigitalTimepiece.new(raw_time: UnstructuredDateTime.new(value: "2021-01-01T10:11:12"))
      dst = TimepieceTransform.transform(src)
      expect(dst.detailed_time.date).to eq("2021-01-01")
      expect(dst.detailed_time.time).to eq("10:11:12")

      back = TimepieceTransform.reverse_transform(dst)
      expect(back.raw_time.value).to eq("2021-01-01T10:11:12")
    end

    it "raises when reversing a model-to-model transform that uses a one-way value transform" do
      user = User.new(birth_date: Date.today)
      expect { OneWayModelTransform.reverse_transform(user) }.to raise_error(Lutaml::Model::ReverseTransformBlockNotDefinedError)
    end
  end
end
