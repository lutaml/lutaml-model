# frozen_string_literal: true

require "spec_helper"

# A collection reader has to hand back a collection the caller can push onto.
#
# Four different readers broke that in four different ways, and only one of
# them made any noise:
#   - the regular reader handed out LAZY_EMPTY_COLLECTION, one frozen Array
#     shared by every instance, so `model.items << x` raised FrozenError;
#   - the register-scoped reader substituted a fresh [] on every call, so the
#     push landed on a throwaway and vanished without a word;
#   - the enum reader returned `i.uniq`, also a fresh Array, same silence;
#   - the reference reader resolved into a fresh Array, same silence again.
module CollectionReaderLivenessSpec
  class Doc < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :items, :string, collection: true
    attribute :others, :string, collection: true

    xml do
      root "doc"
      map_element "name", to: :name
      map_element "item", to: :items
      map_element "other", to: :others
    end
  end

  class Filled < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :items, :string, collection: true, initialize_empty: true

    xml do
      root "doc"
      map_element "name", to: :name
      map_element "item", to: :items
    end

    key_value do
      map "name", to: :name
      map "item", to: :items
    end
  end

  # A model is allowed to define its own writer, and the generated reader has
  # to cope with whatever that writer stored.
  class RolesOwnWriter < Lutaml::Model::Serializable
    attribute :roles, :integer, values: [1, 2, 3], collection: true

    def roles=(value)
      @roles = Set.new(value)
    end
  end

  # A model whose own writer keeps the value somewhere else, so the enum ivar
  # is never written and the reader meets a bare nil.
  class RolesLazyWriter < Lutaml::Model::Serializable
    attribute :roles, :string, values: %w[reader writer admin],
                               collection: true

    def roles=(value)
      @stashed = value
    end
  end

  # A reader the model defines itself can hand back anything at all, including
  # one array shared by every instance. Deliberately not duplicated — sharing
  # is the whole point, and a writer that mutated it would reach every model.
  SHARED_ROLES = [] # rubocop:disable Style/MutableConstant -- shared on purpose

  class RolesOwnReader < Lutaml::Model::Serializable
    attribute :roles, :string, values: %w[reader writer admin],
                               collection: true

    def roles
      @roles ||= SHARED_ROLES
    end
  end

  class RolesSetReader < Lutaml::Model::Serializable
    attribute :roles, :string, values: %w[reader writer admin],
                               collection: true

    def roles
      @roles ||= Set.new
    end
  end

  class RolesFrozenDuplicates < Lutaml::Model::Serializable
    attribute :roles, :string, values: %w[reader writer admin],
                               collection: true

    def roles=(_value)
      @roles = %w[admin admin].freeze
    end
  end

  class RefAuthor < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :name, :string

    xml do
      root "author"
      map_element "id", to: :id
      map_element "name", to: :name
    end
  end

  class RefBook < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :co_authors, { ref: ["CollectionReaderLivenessSpec::RefAuthor", :id] },
              collection: true, default: []

    xml do
      root "book"
      map_element "id", to: :id
      map_element "coAuthor", to: :co_authors
    end
  end

  class Roles < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :roles, :string, values: %w[reader writer admin], collection: true

    xml do
      root "roles"
      map_element "name", to: :name
      map_element "role", to: :roles
    end
  end
end

RSpec.describe "what a collection reader hands back" do
  let(:sentinel) { Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION }
  let(:bare) { "<doc><name>n</name></doc>" }

  describe "the regular collection reader" do
    it "keeps an item pushed onto a collection the document omitted" do
      model = CollectionReaderLivenessSpec::Doc.from_xml(bare)

      model.items << "kept"

      expect(model.items).to eq(["kept"])
    end

    it "carries that item into the document" do
      model = CollectionReaderLivenessSpec::Doc.from_xml(bare)
      model.items << "kept"

      expect(model.to_xml.to_s).to include("<item>kept</item>")
    end

    it "gives each instance its own array" do
      one = CollectionReaderLivenessSpec::Doc.from_xml(bare)
      two = CollectionReaderLivenessSpec::Doc.from_xml(bare)

      one.items << "mine"

      expect(two.items).to eq([])
    end

    it "leaves the collections nobody read on the shared sentinel" do
      model = CollectionReaderLivenessSpec::Doc.from_xml(bare)

      model.items

      expect(model.instance_variable_get(:@others)).to be(sentinel)
    end

    it "keeps the sentinel on a frozen model rather than raising" do
      model = CollectionReaderLivenessSpec::Doc.from_xml(bare).freeze

      expect(model.items).to be(sentinel)
    end

    # Reading must not be observable in the output. Every earlier round of
    # this fix was refuted by a change in what got emitted.
    %w[xml json yaml].each do |format|
      it "does not change to_#{format} just because something read it" do
        quiet = CollectionReaderLivenessSpec::Doc.from_xml(bare)
        peeked = CollectionReaderLivenessSpec::Doc.from_xml(bare)
        peeked.items
        peeked.others

        expect(peeked.public_send(:"to_#{format}").to_s)
          .to eq(quiet.public_send(:"to_#{format}").to_s)
      end
    end
  end

  describe "the enum collection reader" do
    it "keeps an item pushed onto an empty enum collection" do
      model = CollectionReaderLivenessSpec::Roles.from_xml(
        "<roles><name>n</name></roles>",
      )

      model.roles << "admin"

      expect(model.roles).to eq(["admin"])
    end

    it "keeps an item pushed onto a populated enum collection" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: ["reader"])

      model.roles << "writer"

      expect(model.roles).to eq(%w[reader writer])
    end

    it "carries that item into the document" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: ["reader"])
      model.roles << "writer"

      expect(model.to_xml.to_s).to include("<role>writer</role>")
    end

    it "still hides duplicates the way the reader used to" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n")
      model.roles = ["reader"]
      model.roles = %w[reader writer]

      expect(model.roles).to eq(%w[reader writer])
    end

    it "still answers the shorthand predicate" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: ["admin"])

      expect(model.admin?).to be(true)
      expect(model.reader?).to be(false)
    end

    # Handing back the stored Array must not cost the guarantees the old
    # `uniq` reader gave.
    it "still reads unique after a duplicate is pushed through the reader" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: ["admin"])

      model.roles << "admin"

      expect(model.roles).to eq(["admin"])
    end

    # The reader hands out the stored Array, so a writer must not mutate it.
    # Every write builds a new Array, the way it did before the reader went
    # live, which keeps a shared or frozen backing value safe.
    it "does not write through into an array a caller already holds" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: ["admin"])
      held = model.roles

      model.roles = ["reader"]

      expect(held).to eq(["admin"])
      expect(model.roles).to eq(%w[admin reader])
    end

    it "does not duplicate into a held array through the shorthand writer" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: ["admin"])
      held = model.roles

      model.admin = true

      expect(held).to eq(["admin"])
    end

    it "hands back a stored array even when nothing ever wrote the ivar" do
      model = CollectionReaderLivenessSpec::RolesLazyWriter.new

      model.roles << "admin"

      expect(model.roles).to eq(["admin"])
    end

    it "does not write through into a reader the model defines itself" do
      CollectionReaderLivenessSpec::SHARED_ROLES.clear
      one = CollectionReaderLivenessSpec::RolesOwnReader.new
      two = CollectionReaderLivenessSpec::RolesOwnReader.new

      one.roles = ["admin"]

      expect(one.roles).to eq(["admin"])
      expect(two.roles).to eq([])
      expect(CollectionReaderLivenessSpec::SHARED_ROLES).to eq([])
    end

    it "assigns through a reader that hands back something other than an array" do
      model = CollectionReaderLivenessSpec::RolesSetReader.new

      model.roles = ["admin"]

      expect(model.roles).to eq(Set.new(["admin"]))
    end

    it "does not remove through into a held array via the shorthand writer" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: %w[admin reader])
      held = model.roles

      model.admin = false

      expect(held).to eq(%w[admin reader])
      expect(model.roles).to eq(["reader"])
    end

    it "does not mutate through the shorthand writer on a frozen model" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: ["admin"])
      held = model.roles
      model.freeze

      expect { model.writer = true }.to raise_error(FrozenError)
      expect(held).to eq(["admin"])
    end

    it "reads a frozen backing array as unique" do
      model = CollectionReaderLivenessSpec::RolesFrozenDuplicates.new
      model.roles = ["admin"]

      expect(model.roles).to eq(["admin"])
    end

    it "leaves a backing value its own writer stored alone" do
      model = CollectionReaderLivenessSpec::RolesOwnWriter.new
      model.roles = [1, 2]

      expect(model.roles).to eq([1, 2])
      expect(model.instance_variable_get(:@roles)).to eq(Set.new([1, 2]))
    end

    it "does not touch the collection when a frozen model rejects the write" do
      model = CollectionReaderLivenessSpec::Roles.new(name: "n",
                                                      roles: ["admin"])
      model.roles
      model.freeze

      expect { model.roles = ["reader"] }.to raise_error(FrozenError)
      expect(model.instance_variable_get(:@roles)).to eq(["admin"])
    end
  end

  describe "the register-scoped collection reader" do
    # initialization.rb defines its own pair of collection methods. Round 5
    # could not reach them through the public API, so drive the generator
    # directly rather than assume the row is unreachable and therefore fine.
    let(:host) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name
          "CollectionReaderLivenessSpec::RegisterScopedHost"
        end

        attribute :notes, :string, collection: true
      end
    end

    let(:instance) do
      host.send(:remove_method, :notes)
      host.send(:remove_method, :notes=)
      host.singleton_class.send(:public, :define_collection_register_methods)
      host.define_collection_register_methods(:notes)

      inst = host.allocate
      inst.send(:finalize_deserialization, nil)
      inst
    end

    it "is the reader under test" do
      expect(instance.method(:notes).source_location.first)
        .to end_with("serialize/initialization.rb")
    end

    it "keeps an item pushed through it" do
      instance.notes << "kept"

      expect(instance.notes).to eq(["kept"])
    end

    it "keeps an item appended builder-style" do
      instance.notes("kept")

      expect(instance.notes).to eq(["kept"])
    end
  end

  describe "the reference collection reader" do
    let(:author) do
      CollectionReaderLivenessSpec::RefAuthor.new(id: "a2", name: "Two")
    end

    it "keeps an item pushed onto an empty reference collection" do
      book = CollectionReaderLivenessSpec::RefBook.new(id: "b")

      book.co_authors << author

      expect(book.co_authors).to eq([author])
    end

    it "keeps an item pushed onto a populated reference collection" do
      CollectionReaderLivenessSpec::RefAuthor.new(id: "a1", name: "One")
      book = CollectionReaderLivenessSpec::RefBook.new(id: "b",
                                                       co_authors: ["a1"])

      book.co_authors << author

      expect(book.co_authors.map(&:id)).to eq(%w[a1 a2])
    end

    it "carries that item into the document" do
      book = CollectionReaderLivenessSpec::RefBook.new(id: "b")
      book.co_authors << author

      expect(book.to_xml.to_s).to include("<coAuthor>a2</coAuthor>")
    end

    it "still reads the keys back once the objects are stored" do
      CollectionReaderLivenessSpec::RefAuthor.new(id: "a1", name: "One")
      book = CollectionReaderLivenessSpec::RefBook.new(id: "b",
                                                       co_authors: ["a1"])

      book.co_authors # resolves, and stores what it resolved

      expect(book.co_authors_ids).to eq(["a1"])
    end

    it "stays live when the collection also holds a raw nil" do
      CollectionReaderLivenessSpec::RefAuthor.new(id: "a1", name: "One")
      book = CollectionReaderLivenessSpec::RefBook.new(
        id: "b", co_authors: ["a1", nil],
      )

      book.co_authors << author

      expect(book.co_authors.size).to eq(3)
      expect(book.co_authors[1]).to be_nil
      expect(book.co_authors.compact.map(&:id)).to eq(%w[a1 a2])
    end

    it "keeps re-resolving while any reference is still dangling" do
      book = CollectionReaderLivenessSpec::RefBook.new(id: "b",
                                                       co_authors: ["late"])

      expect(book.co_authors).to eq([nil])

      CollectionReaderLivenessSpec::RefAuthor.new(id: "late", name: "Late")

      expect(book.co_authors.map(&:id)).to eq(["late"])
    end
  end

  describe "every construction entry point" do
    # The readers above are reached through from_xml. A collection that the
    # model actually holds has to come back live from all of them, not just
    # that one.
    let(:entry_points) do
      {
        "new" => -> { CollectionReaderLivenessSpec::Filled.new },
        "new with attributes" => lambda {
          CollectionReaderLivenessSpec::Filled.new(name: "n")
        },
        "from_xml" => lambda {
          CollectionReaderLivenessSpec::Filled.from_xml(bare)
        },
        "from_json" => lambda {
          CollectionReaderLivenessSpec::Filled.from_json('{"name":"n"}')
        },
        "from_yaml" => lambda {
          CollectionReaderLivenessSpec::Filled.from_yaml("name: n\n")
        },
        "from_hash" => lambda {
          CollectionReaderLivenessSpec::Filled.from_hash({ "name" => "n" })
        },
        "from_toml" => lambda {
          CollectionReaderLivenessSpec::Filled.from_toml(%(name = "n"\n))
        },
        "dup" => lambda {
          CollectionReaderLivenessSpec::Filled.from_xml(bare).dup
        },
        "clone" => lambda {
          CollectionReaderLivenessSpec::Filled.from_xml(bare).clone
        },
      }
    end

    it "hands back the same array on every read" do
      results = entry_points.transform_values do |build|
        model = build.call
        model.items.equal?(model.items)
      end

      expect(results).to all(satisfy { |_name, same| same })
    end

    it "keeps an item pushed through the reader" do
      results = entry_points.transform_values do |build|
        model = build.call
        model.items << "kept"
        model.items
      end

      expect(results.values).to all(eq(["kept"]))
    end

    it "carries that item into the document" do
      results = entry_points.transform_values do |build|
        model = build.call
        model.items << "kept"
        model.to_xml.to_s.include?("<item>kept</item>")
      end

      expect(results).to all(satisfy { |_name, reached| reached })
    end
  end
end
