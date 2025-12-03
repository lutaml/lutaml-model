require "spec_helper"
require "lutaml/model"

module CollectionValidationTests
  class Publication < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :title, :string
    attribute :year, :integer
    attribute :author, :string
    attribute :category, :string

    xml do
      root "publication"
      map_attribute "id", to: :id
      map_element "title", to: :title
      map_element "year", to: :year
      map_element "author", to: :author
      map_element "category", to: :category
    end

    key_value do
      map "id", to: :id
      map "title", to: :title
      map "year", to: :year
      map "author", to: :author
      map "category", to: :category
    end
  end

  # Collection with uniqueness validation
  class UniquePublicationCollection < Lutaml::Model::Collection
    instances :publications, Publication
    validates_uniqueness_of :id, message: "Publication IDs must be unique"

    xml do
      root "publications"
      map_element "publication", to: :publications
    end

    key_value do
      map_instances to: :publications
    end
  end

  # Collection with count validations
  class SizedPublicationCollection < Lutaml::Model::Collection
    instances :publications, Publication
    validates_min_count 2, message: "Must have at least 2 publications"
    validates_max_count 5, message: "Cannot have more than 5 publications"

    xml do
      root "publications"
      map_element "publication", to: :publications
    end

    key_value do
      map_instances to: :publications
    end
  end

  # Collection with "all must have" validation
  class CompletePublicationCollection < Lutaml::Model::Collection
    instances :publications, Publication
    validates_all_present :author, message: "All publications must have an author"
    validates_all_present :year, message: "All publications must have a year"

    xml do
      root "publications"
      map_element "publication", to: :publications
    end

    key_value do
      map_instances to: :publications
    end
  end

  # Collection with custom collection-level validation
  class CustomValidatedPublicationCollection < Lutaml::Model::Collection
    instances :publications, Publication

    # Custom collection validation to ensure publication years are sequential
    validate_collection do |publications, errors|
      return if publications.empty?

      years = publications.filter_map(&:year).sort
      (1...years.length).each do |i|
        unless years[i] == years[i - 1] + 1
          errors.add(:collection, "Publication years must be sequential")
          break
        end
      end
    end

    # Another custom validation
    validate_collection do |publications, errors|
      categories = publications.filter_map(&:category)
      if categories.uniq.length < 2
        errors.add(:collection, "Collection must have publications from at least 2 different categories")
      end
    end

    xml do
      root "publications"
      map_element "publication", to: :publications
    end

    key_value do
      map_instances to: :publications
    end
  end

  # Collection with both instance and collection validations
  class MixedValidationPublicationCollection < Lutaml::Model::Collection
    instances(:publications, Publication) do
      validates :year, numericality: { greater_than: 1900 }  # Instance-level validation
      validates :title, presence: true                       # Instance-level validation
    end

    validates_uniqueness_of :id                              # Collection-level validation
    validates_min_count 1                                    # Collection-level validation

    xml do
      root "publications"
      map_element "publication", to: :publications
    end

    key_value do
      map_instances to: :publications
    end
  end
end

RSpec.describe Lutaml::Model::Collection do
  let(:science_publication) do
    CollectionValidationTests::Publication.new(
      id: "1",
      title: "Title 1",
      year: 2020,
      author: "Author 1",
      category: "Science",
    )
  end

  let(:fiction_publication) do
    CollectionValidationTests::Publication.new(
      id: "2",
      title: "Title 2",
      year: 2021,
      author: "Author 2",
      category: "Fiction",
    )
  end

  let(:history_publication) do
    CollectionValidationTests::Publication.new(
      id: "3",
      title: "Title 3",
      year: 2022,
      author: "Author 3",
      category: "History",
    )
  end

  let(:duplicate_id_publication) do
    CollectionValidationTests::Publication.new(
      id: "1", # Same as science_publication
      title: "Different Title",
      year: 2023,
      author: "Different Author",
      category: "Science",
    )
  end

  let(:publication_without_author) do
    CollectionValidationTests::Publication.new(
      id: "4",
      title: "Title 4",
      year: 2020,
      category: "Science",
    )
  end

  describe "Collection Validation" do
    describe "Uniqueness validation" do
      context "with unique IDs" do
        it "validates successfully" do
          collection = CollectionValidationTests::UniquePublicationCollection.new([science_publication, fiction_publication, history_publication])
          expect { collection.validate! }.not_to raise_error
        end
      end

      context "with duplicate IDs" do
        it "raises validation error" do
          collection = CollectionValidationTests::UniquePublicationCollection.new([science_publication, duplicate_id_publication])
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("Publication IDs must be unique")
          end
        end
      end

      context "with empty collection" do
        it "validates successfully" do
          collection = CollectionValidationTests::UniquePublicationCollection.new([])
          expect { collection.validate! }.not_to raise_error
        end
      end

      context "with nil values" do
        it "ignores nil values in uniqueness validation" do
          nil_id_pub1 = CollectionValidationTests::Publication.new(id: nil, title: "Title 1", year: 2020, author: "Author 1", category: "Science")
          nil_id_pub2 = CollectionValidationTests::Publication.new(id: nil, title: "Title 2", year: 2021, author: "Author 2", category: "Fiction")

          # Multiple nils are allowed
          collection = CollectionValidationTests::UniquePublicationCollection.new([nil_id_pub1, nil_id_pub2])
          expect { collection.validate! }.not_to raise_error

          # Nils mixed with non-nil values are allowed
          collection = CollectionValidationTests::UniquePublicationCollection.new([science_publication, nil_id_pub1])
          expect { collection.validate! }.not_to raise_error
        end
      end
    end

    describe "Count validations" do
      context "with valid count" do
        it "validates successfully with 2-5 items" do
          collection = CollectionValidationTests::SizedPublicationCollection.new([science_publication, fiction_publication])
          expect { collection.validate! }.not_to raise_error

          collection = CollectionValidationTests::SizedPublicationCollection.new([science_publication, fiction_publication, history_publication])
          expect { collection.validate! }.not_to raise_error
        end
      end

      context "with too few items" do
        it "raises validation error" do
          collection = CollectionValidationTests::SizedPublicationCollection.new([science_publication])
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("Must have at least 2 publications")
          end
        end
      end

      context "with too many items" do
        it "raises validation error" do
          pubs = [science_publication, fiction_publication, history_publication, publication_without_author, duplicate_id_publication,
                  CollectionValidationTests::Publication.new(id: "6", title: "Title 6", year: 2024, author: "Author 6", category: "Science")]
          collection = CollectionValidationTests::SizedPublicationCollection.new(pubs)
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("Cannot have more than 5 publications")
          end
        end
      end

      context "with empty collection" do
        it "raises validation error for minimum count" do
          collection = CollectionValidationTests::SizedPublicationCollection.new([])
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("Must have at least 2 publications")
          end
        end
      end
    end

    describe "All must have validation" do
      context "when all items have required fields" do
        it "validates successfully" do
          collection = CollectionValidationTests::CompletePublicationCollection.new([science_publication, fiction_publication, history_publication])
          expect { collection.validate! }.not_to raise_error
        end
      end

      context "when some items are missing required fields" do
        it "raises validation error for missing author" do
          collection = CollectionValidationTests::CompletePublicationCollection.new([science_publication, publication_without_author])
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("All publications must have an author")
          end
        end
      end

      context "with empty collection" do
        it "validates successfully" do
          collection = CollectionValidationTests::CompletePublicationCollection.new([])
          expect { collection.validate! }.not_to raise_error
        end
      end

      context "with nil and empty string values" do
        it "raises validation error for both nil and empty string" do
          nil_author = CollectionValidationTests::Publication.new(id: "1", title: "Title", year: 2020, author: nil, category: "Science")
          empty_author = CollectionValidationTests::Publication.new(id: "2", title: "Title", year: 2021, author: "", category: "Fiction")

          # Both nil and empty string should fail
          [nil_author, empty_author].each do |pub|
            collection = CollectionValidationTests::CompletePublicationCollection.new([science_publication, pub])
            expect do
              collection.validate!
            end.to raise_error(Lutaml::Model::ValidationError) do |error|
              expect(error.message).to include("All publications must have an author")
            end
          end
        end
      end
    end

    describe "Custom collection validation" do
      context "with valid sequential years and multiple categories" do
        let(:sequential_pubs) do
          [
            CollectionValidationTests::Publication.new(id: "1", title: "Title 1", year: 2020, author: "Author 1", category: "Science"),
            CollectionValidationTests::Publication.new(id: "2", title: "Title 2", year: 2021, author: "Author 2", category: "Fiction"),
          ]
        end

        it "validates successfully" do
          collection = CollectionValidationTests::CustomValidatedPublicationCollection.new(sequential_pubs)
          expect { collection.validate! }.not_to raise_error
        end
      end

      context "with non-sequential years" do
        let(:non_sequential_pubs) do
          [
            CollectionValidationTests::Publication.new(id: "1", title: "Title 1", year: 2020, author: "Author 1", category: "Science"),
            CollectionValidationTests::Publication.new(id: "2", title: "Title 2", year: 2022, author: "Author 2", category: "Fiction"), # Gap in years
          ]
        end

        it "raises validation error" do
          collection = CollectionValidationTests::CustomValidatedPublicationCollection.new(non_sequential_pubs)
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("Publication years must be sequential")
          end
        end
      end

      context "with single category" do
        let(:same_category_pubs) do
          [
            CollectionValidationTests::Publication.new(id: "1", title: "Title 1", year: 2020, author: "Author 1", category: "Science"),
            CollectionValidationTests::Publication.new(id: "2", title: "Title 2", year: 2021, author: "Author 2", category: "Science"),
          ]
        end

        it "raises validation error" do
          collection = CollectionValidationTests::CustomValidatedPublicationCollection.new(same_category_pubs)
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("Collection must have publications from at least 2 different categories")
          end
        end
      end
    end

    describe "Mixed instance and collection validations" do
      context "with valid instance and collection data" do
        it "validates successfully" do
          collection = CollectionValidationTests::MixedValidationPublicationCollection.new([science_publication, fiction_publication])
          expect { collection.validate! }.not_to raise_error
        end
      end

      context "with invalid instance data" do
        let(:old_pub) do
          CollectionValidationTests::Publication.new(
            id: "old",
            title: "Old Title",
            year: 1800, # Too old
            author: "Old Author",
            category: "History",
          )
        end

        it "raises validation error for instance validation" do
          collection = CollectionValidationTests::MixedValidationPublicationCollection.new([old_pub])
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("year value is `1800`, which is not greater than 1900")
          end
        end
      end

      context "with invalid collection data" do
        it "raises validation error for duplicate IDs" do
          collection = CollectionValidationTests::MixedValidationPublicationCollection.new([science_publication, duplicate_id_publication])
          expect do
            collection.validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("id values must be unique")
          end
        end
      end
    end
  end
end
