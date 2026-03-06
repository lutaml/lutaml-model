require "spec_helper"
require "lutaml/model"

module CollectionIndexTests
  class Person < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :name, :string
    attribute :email, :string
    attribute :slug, :string
  end
end

RSpec.describe "Collection index_by" do
  describe "single index" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :people, CollectionIndexTests::Person
        index_by :id
      end
    end

    let(:people_data) do
      [
        { id: "001", name: "Alice", email: "alice@example.com" },
        { id: "002", name: "Bob", email: "bob@example.com" },
        { id: "003", name: "Charlie", email: "charlie@example.com" },
      ]
    end

    let(:collection) { collection_class.new(people_data) }

    describe "#fetch" do
      it "finds an item by key using O(1) lookup" do
        person = collection.fetch("001")
        expect(person).to be_a(CollectionIndexTests::Person)
        expect(person.name).to eq("Alice")
      end

      it "returns nil for missing key" do
        expect(collection.fetch("999")).to be_nil
      end

      it "returns nil for nil key" do
        expect(collection.fetch(nil)).to be_nil
      end
    end

    describe "#find_by" do
      it "finds an item by field and key" do
        person = collection.find_by(:id, "002")
        expect(person).to be_a(CollectionIndexTests::Person)
        expect(person.name).to eq("Bob")
      end

      it "returns nil for missing key" do
        expect(collection.find_by(:id, "999")).to be_nil
      end

      it "returns nil for non-indexed field" do
        expect(collection.find_by(:email, "alice@example.com")).to be_nil
      end

      it "accepts string field names" do
        person = collection.find_by("id", "003")
        expect(person.name).to eq("Charlie")
      end
    end

    describe "#index_caches" do
      it "returns the built index cache" do
        expect(collection.index_caches).to be_a(Hash)
        expect(collection.index_caches[:id]).to be_a(Hash)
        expect(collection.index_caches[:id].keys).to contain_exactly("001", "002", "003")
      end
    end

    describe "index updates on mutation" do
      it "rebuilds index after #push" do
        collection.push(CollectionIndexTests::Person.new(id: "004", name: "Diana"))

        expect(collection.fetch("004")).not_to be_nil
        expect(collection.fetch("004").name).to eq("Diana")
      end

      it "rebuilds index after #<<" do
        collection << CollectionIndexTests::Person.new(id: "005", name: "Eve")

        expect(collection.fetch("005")).not_to be_nil
        expect(collection.fetch("005").name).to eq("Eve")
      end

      it "rebuilds index after #[]=" do
        collection[0] = CollectionIndexTests::Person.new(id: "006", name: "Frank")

        expect(collection.fetch("006")).not_to be_nil
        expect(collection.fetch("006").name).to eq("Frank")
      end

      it "rebuilds index after #collection=" do
        collection.collection = [
          CollectionIndexTests::Person.new(id: "007", name: "Grace"),
        ]

        expect(collection.fetch("007")).not_to be_nil
        expect(collection.fetch("001")).to be_nil
      end
    end
  end

  describe "multiple indexes" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :people, CollectionIndexTests::Person
        index_by :id, :email, :slug
      end
    end

    let(:people_data) do
      [
        { id: "001", name: "Alice", email: "alice@example.com", slug: "alice" },
        { id: "002", name: "Bob", email: "bob@example.com", slug: "bob" },
        { id: "003", name: "Charlie", email: "charlie@example.com", slug: "charlie" },
      ]
    end

    let(:collection) { collection_class.new(people_data) }

    describe "#find_by" do
      it "finds an item by id" do
        person = collection.find_by(:id, "001")
        expect(person.name).to eq("Alice")
      end

      it "finds an item by email" do
        person = collection.find_by(:email, "bob@example.com")
        expect(person.name).to eq("Bob")
      end

      it "finds an item by slug" do
        person = collection.find_by(:slug, "charlie")
        expect(person.name).to eq("Charlie")
      end

      it "returns nil for missing key on any index" do
        expect(collection.find_by(:id, "999")).to be_nil
        expect(collection.find_by(:email, "missing@example.com")).to be_nil
        expect(collection.find_by(:slug, "missing")).to be_nil
      end
    end

    describe "#fetch" do
      it "raises ArgumentError when multiple indexes are configured" do
        expect do
          collection.fetch("001")
        end.to raise_error(ArgumentError, /#fetch only works with single index/)
      end
    end

    describe "#index_caches" do
      it "builds separate caches for each index" do
        expect(collection.index_caches.keys).to contain_exactly(:id, :email, :slug)
      end
    end
  end

  describe "named indexes with procs" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :people, CollectionIndexTests::Person
        index_by :id
        index :email, by: ->(item) { item.email.downcase }
      end
    end

    let(:people_data) do
      [
        { id: "001", name: "Alice", email: "ALICE@EXAMPLE.COM" },
        { id: "002", name: "Bob", email: "BOB@EXAMPLE.COM" },
      ]
    end

    let(:collection) { collection_class.new(people_data) }

    describe "#find_by" do
      it "finds item using proc-based index" do
        person = collection.find_by(:email, "alice@example.com")
        expect(person.name).to eq("Alice")
      end

      it "stores lowercase key via proc" do
        # The proc lowercases the key, so lookup must use lowercase
        person = collection.find_by(:email, "alice@example.com")
        expect(person).not_to be_nil
        expect(person.name).to eq("Alice")
      end

      it "still finds by regular index" do
        person = collection.find_by(:id, "002")
        expect(person.name).to eq("Bob")
      end
    end
  end

  describe "proc without name raises error" do
    it "raises ArgumentError when proc is passed to index_by" do
      expect do
        Class.new(Lutaml::Model::Collection) do
          instances :people, CollectionIndexTests::Person
          index_by ->(item) { item.email.downcase }
        end
      end.to raise_error(ArgumentError, /Proc indexes require a name/)
    end
  end

  describe "with sorting" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :people, CollectionIndexTests::Person
        index_by :id
        sort by: :name, order: :asc
      end
    end

    let(:people_data) do
      [
        { id: "001", name: "Charlie" },
        { id: "002", name: "Alice" },
        { id: "003", name: "Bob" },
      ]
    end

    let(:collection) { collection_class.new(people_data) }

    it "sorts items and indexes them" do
      # Check sorting
      expect(collection.map(&:name)).to eq(["Alice", "Bob", "Charlie"])

      # Check indexing still works
      expect(collection.fetch("001").name).to eq("Charlie")
      expect(collection.fetch("002").name).to eq("Alice")
      expect(collection.fetch("003").name).to eq("Bob")
    end
  end

  describe "empty collection" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :people, CollectionIndexTests::Person
        index_by :id
      end
    end

    let(:collection) { collection_class.new([]) }

    it "returns nil from find_by on empty collection" do
      expect(collection.find_by(:id, "001")).to be_nil
    end

    it "returns nil from fetch on empty collection" do
      expect(collection.fetch("001")).to be_nil
    end

    it "returns nil index_caches for empty collection" do
      expect(collection.index_caches).to be_nil
    end
  end

  describe "collection without index" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :people, CollectionIndexTests::Person
      end
    end

    let(:collection) { collection_class.new([{ id: "001", name: "Alice" }]) }

    it "returns nil from find_by when no indexes configured" do
      expect(collection.find_by(:id, "001")).to be_nil
    end

    it "returns nil index_caches when no indexes configured" do
      expect(collection.index_caches).to be_nil
    end
  end

  describe "duplicate keys" do
    let(:collection_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :people, CollectionIndexTests::Person
        index_by :id
      end
    end

    let(:people_data) do
      [
        { id: "001", name: "Alice" },
        { id: "001", name: "Alice Duplicate" }, # Same ID
        { id: "002", name: "Bob" },
      ]
    end

    let(:collection) { collection_class.new(people_data) }

    it "last item with duplicate key wins" do
      person = collection.fetch("001")
      expect(person.name).to eq("Alice Duplicate")
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(Lutaml::Model::Collection) do
        instances :people, CollectionIndexTests::Person
        index_by :id
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        index_by :email
      end
    end

    let(:collection) { child_class.new([{ id: "001", name: "Alice", email: "alice@example.com" }]) }

    it "child class has its own indexes" do
      # Child should have :email index (overwrites parent's :id)
      person = collection.find_by(:email, "alice@example.com")
      expect(person.name).to eq("Alice")
    end

    it "parent class retains its indexes" do
      parent_collection = parent_class.new([{ id: "001", name: "Alice", email: "alice@example.com" }])
      person = parent_collection.fetch("001")
      expect(person.name).to eq("Alice")
    end
  end
end
