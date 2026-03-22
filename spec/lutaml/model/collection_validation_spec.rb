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

    describe "Validation chaining with context" do
      context "with context sharing between validations" do
        it "allows validations to read results from previous validations" do
          chain_executed = []

          chained_collection = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validates_uniqueness_of :id

            validate_collection do |_collection, _errors, ctx|
              chain_executed << :first
              ctx[:duplicates_found] = !ctx[:duplicates_of_id].nil? && ctx[:duplicates_of_id].any?
            end

            validate_collection do |_collection, errors, ctx|
              chain_executed << :second
              if ctx[:duplicates_found]
                errors.add(:collection, "Cannot proceed with duplicates")
              end
            end
          end

          # Test with duplicates
          collection = chained_collection.new([science_publication, duplicate_id_publication])
          expect { collection.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("Cannot proceed with duplicates")
          end
          expect(chain_executed).to eq([:first, :second])

          # Test without duplicates
          chain_executed.clear
          collection = chained_collection.new([science_publication, fiction_publication])
          expect { collection.validate! }.not_to raise_error
          expect(chain_executed).to eq([:first, :second])
        end

        it "stores duplicate values in context for downstream validations" do
          chained_collection = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validates_uniqueness_of :id

            validate_collection do |_collection, errors, ctx|
              if ctx[:duplicates_of_id]&.include?("1")
                errors.add(:collection, "Found duplicate ID: 1")
              end
            end
          end

          collection = chained_collection.new([science_publication, duplicate_id_publication])
          expect { collection.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("Found duplicate ID: 1")
          end
        end

        it "stores missing count in context for validates_all_present" do
          chained_collection = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validates_all_present :author

            validate_collection do |_collection, errors, ctx|
              if ctx[:missing_author_count].to_i > 0
                errors.add(:collection, "#{ctx[:missing_author_count]} items missing author")
              end
            end
          end

          collection = chained_collection.new([science_publication, publication_without_author])
          expect { collection.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to include("1 items missing author")
          end
        end
      end

      context "with conditional validation using :if_cond option" do
        it "only runs validation when condition is met" do
          chained_collection = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validates_uniqueness_of :id

            validate_collection(if_cond: ->(ctx) { ctx[:duplicates_of_id]&.any? }) do |_collection, errors, _ctx|
              errors.add(:collection, "Validation ran because duplicates exist")
            end
          end

          # With duplicates - conditional validation should run
          collection = chained_collection.new([science_publication, duplicate_id_publication])
          errors = collection.validate
          error_messages = errors.map(&:message).join
          expect(error_messages).to include("Validation ran because duplicates exist")
          expect(error_messages).to include("id values must be unique")

          # Without duplicates - conditional validation should not run
          collection = chained_collection.new([science_publication, fiction_publication])
          errors = collection.validate
          expect(errors).to be_empty
        end

        it "can skip validation based on context state" do
          expensive_validation_ran = false

          chained_collection = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validates_uniqueness_of :id

            # This validation should only run if there are NO duplicates
            validate_collection(if_cond: ->(ctx) { !ctx[:duplicates_of_id]&.any? }) do |_collection, _errors, _ctx|
              expensive_validation_ran = true
            end
          end

          # With duplicates - expensive validation should skip
          collection = chained_collection.new([science_publication, duplicate_id_publication])
          errors = collection.validate
          expect(errors.map(&:message).join).to include("id values must be unique")
          expect(expensive_validation_ran).to be false

          # Without duplicates - expensive validation should run
          expensive_validation_ran = false
          collection = chained_collection.new([science_publication, fiction_publication])
          errors = collection.validate
          expect(errors).to be_empty
          expect(expensive_validation_ran).to be true
        end
      end

      context "with conditional validation using :unless_cond option" do
        it "skips validation when condition is met" do
          ran_count = 0

          chained_collection = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validates_uniqueness_of :id

            # Skip when duplicates exist
            validate_collection(unless_cond: ->(ctx) { ctx[:duplicates_of_id]&.any? }) do |_collection, _errors, _ctx|
              ran_count += 1
            end
          end

          # With duplicates - should skip (unless_cond returns true, so validation is skipped)
          collection = chained_collection.new([science_publication, duplicate_id_publication])
          collection.validate
          expect(ran_count).to be 0

          # Without duplicates - should run (unless_cond returns false, so validation runs)
          collection = chained_collection.new([science_publication, fiction_publication])
          collection.validate
          expect(ran_count).to be 1
        end
      end

      context "with ctx.stop!" do
        it "stops validation chain when ctx.stop! is called" do
          chain_order = []

          chained_collection = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validate_collection do |_collection, _errors, ctx|
              chain_order << :first
              ctx.stop!
            end

            validate_collection do |_collection, _errors, ctx|
              chain_order << :second
              ctx.stop!
            end

            validate_collection do |_collection, _errors, _ctx|
              chain_order << :third
            end
          end

          collection = chained_collection.new([science_publication])
          collection.validate!
          expect(chain_order).to eq([:first])
        end
      end

      context "with backwards compatible block signatures" do
        it "works with 1-argument blocks" do
          ran = false

          collection_class = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validate_collection do |collection|
              ran = true if !collection.empty?
            end
          end

          collection = collection_class.new([science_publication])
          collection.validate!
          expect(ran).to be true
        end

        it "works with 2-argument blocks (original signature)" do
          ran_args = []

          collection_class = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validate_collection do |collection, errors|
              ran_args << [collection.size, errors.class.name]
              errors.add(:collection, "Test error") if !collection.empty?
            end
          end

          collection = collection_class.new([science_publication])
          errors = collection.validate
          expect(ran_args.first.first).to eq 1
          expect(ran_args.first.last).to include("Errors")
          expect(errors.map(&:message).first).to include("Test error")
        end

        it "works with 3-argument blocks (new signature with context)" do
          received_context = nil

          collection_class = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validate_collection do |_collection, _errors, ctx|
              received_context = ctx
              ctx[:test_value] = "from_validation"
            end
          end

          collection = collection_class.new([science_publication])
          collection.validate
          expect(received_context).to be_a(Lutaml::Model::ValidationContext)
          expect(received_context[:test_value]).to eq("from_validation")
        end
      end

      context "with ctx.failed? helper" do
        it "returns true when errors have been added" do
          result = nil

          chained_collection = Class.new(Lutaml::Model::Collection) do
            instances :publications, CollectionValidationTests::Publication

            validates_uniqueness_of :id

            validate_collection do |_collection, _errors, ctx|
              result = ctx.failed?
            end
          end

          # Without errors
          collection = chained_collection.new([science_publication, fiction_publication])
          collection.validate
          expect(result).to be false

          # With errors
          collection = chained_collection.new([science_publication, duplicate_id_publication])
          collection.validate
          expect(result).to be true
        end
      end
    end
  end
end
