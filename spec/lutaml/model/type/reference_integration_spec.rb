require "spec_helper"

class Author < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :name, :string
  attribute :email, :string

  xml do
    root "author"
    map_element "id", to: :id
    map_element "name", to: :name
    map_element "email", to: :email
  end
end

class Book < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :title, :string
  attribute :author_ref, { ref: ["Author", :id] }
  attribute :co_authors, { ref: ["Author", :id] }, collection: true

  xml do
    root "book"
    map_element "id", to: :id
    map_element "title", to: :title
    map_element "authorRef", to: :author_ref
    map_element "coAuthor", to: :co_authors
  end
end

RSpec.describe Lutaml::Model::Type::Reference do
  let(:first_author) { Author.new(id: "author-1", name: "John Doe", email: "john@example.com") }
  let(:second_author) { Author.new(id: "author-2", name: "Jane Smith", email: "jane@example.com") }
  let(:book) { Book.new(id: "book-1", title: "Great Book") }

  before do
    Lutaml::Model::Store.instance.register(first_author)
    Lutaml::Model::Store.instance.register(second_author)
  end

  after do
    Lutaml::Model::Store.instance.clear
  end

  describe "single reference" do
    it "assigns and resolves correctly" do
      book.author_ref = "author-1"

      # New behavior: returns actual resolved object, not Reference instance
      expect(book.author_ref).to be_a(Author)
      expect(book.author_ref.id).to eq("author-1")
      expect(book.author_ref).to eq(first_author)
      expect(book.author_ref.name).to eq("John Doe")
    end
  end

  describe "collection of references" do
    it "assigns and resolves correctly" do
      book.co_authors = ["author-1", "author-2"]

      # New behavior: returns array of actual resolved objects, not Reference instances
      expect(book.co_authors).to all(be_a(Author))
      expect(book.co_authors.map(&:id)).to eq(["author-1", "author-2"])
      expect(book.co_authors).to eq([first_author, second_author])
    end
  end

  describe "YAML round-trip" do
    it "serializes to keys and deserializes to resolved objects" do
      book.author_ref = "author-1"
      book.co_authors = ["author-1", "author-2"]

      yaml_data = book.to_yaml
      expect(yaml_data).to include("author_ref: author-1")
      expect(yaml_data).to include("- author-1")
      expect(yaml_data).to include("- author-2")

      loaded_book = Book.from_yaml(yaml_data)
      # New behavior: returns actual resolved objects
      expect(loaded_book.author_ref).to be_a(Author)
      expect(loaded_book.author_ref.name).to eq("John Doe")
      expect(loaded_book.co_authors.map(&:name)).to eq(["John Doe", "Jane Smith"])
    end
  end

  describe "JSON round-trip" do
    it "serializes to keys and deserializes to resolved objects" do
      book.author_ref = "author-1"
      book.co_authors = ["author-1", "author-2"]

      json_data = book.to_json
      parsed = JSON.parse(json_data)
      expect(parsed["author_ref"]).to eq("author-1")
      expect(parsed["co_authors"]).to eq(["author-1", "author-2"])

      loaded_book = Book.from_json(json_data)
      # New behavior: returns actual resolved objects
      expect(loaded_book.author_ref).to be_a(Author)
      expect(loaded_book.author_ref.name).to eq("John Doe")
      expect(loaded_book.co_authors.map(&:name)).to eq(["John Doe", "Jane Smith"])
    end
  end

  describe "from_* methods" do
    context "when objects auto-register during loading" do
      before { Lutaml::Model::Store.clear }

      it "from_yaml loads and auto-registers objects" do
        yaml_data = <<~YAML
          id: loaded-author
          name: Loaded Author
          email: loaded@example.com
        YAML

        loaded_author = Author.from_yaml(yaml_data)

        expect(loaded_author.name).to eq("Loaded Author")
        expect(loaded_author.id).to eq("loaded-author")

        # Verify auto-registration
        ref = described_class.new("Author", :id, "loaded-author")
        expect(ref.object).to eq(loaded_author)
        expect(ref.object.name).to eq("Loaded Author")
      end

      it "from_json loads and auto-registers objects" do
        json_data = '{"id":"json-author","name":"JSON Author","email":"json@example.com"}'

        loaded_author = Author.from_json(json_data)

        expect(loaded_author.name).to eq("JSON Author")
        expect(loaded_author.id).to eq("json-author")

        # Verify auto-registration
        ref = described_class.new("Author", :id, "json-author")
        expect(ref.object).to eq(loaded_author)
        expect(ref.object.name).to eq("JSON Author")
      end

      it "from_xml loads and auto-registers objects" do
        xml_data = "<author><id>xml-author</id><name>XML Author</name><email>xml@example.com</email></author>"

        loaded_author = Author.from_xml(xml_data)

        expect(loaded_author.name).to eq("XML Author")
        expect(loaded_author.id).to eq("xml-author")

        # Verify auto-registration
        ref = described_class.new("Author", :id, "xml-author")
        expect(ref.object).to eq(loaded_author)
        expect(ref.object.name).to eq("XML Author")
      end

      it "from_hash loads and auto-registers objects" do
        hash_data = {
          "id" => "hash-author",
          "name" => "Hash Author",
          "email" => "hash@example.com",
        }

        loaded_author = Author.from_hash(hash_data)

        expect(loaded_author.name).to eq("Hash Author")
        expect(loaded_author.id).to eq("hash-author")

        # Verify auto-registration
        ref = described_class.new("Author", :id, "hash-author")
        expect(ref.object).to eq(loaded_author)
        expect(ref.object.name).to eq("Hash Author")
      end
    end

    context "when references work immediately after loading" do
      before { Lutaml::Model::Store.clear }

      it "allows cross-format references" do
        # Load author from YAML
        author_yaml = "id: yaml-author\nname: YAML Author\nemail: yaml@example.com"
        yaml_author = Author.from_yaml(author_yaml)

        # Load book from JSON that references the YAML-loaded author
        book_json = {
          "id" => "cross-book",
          "title" => "Cross Format Book",
          "author_ref" => "yaml-author",
          "co_authors" => ["yaml-author"],
        }.to_json

        loaded_book = Book.from_json(book_json)

        # Users work with actual objects, references are internal
        expect(loaded_book.author_ref).to be_a(Author)
        expect(loaded_book.author_ref).to eq(yaml_author)
        expect(loaded_book.author_ref.name).to eq("YAML Author")
        expect(loaded_book.co_authors.first).to eq(yaml_author)
      end

      it "handles multiple objects from same format" do
        # Load multiple authors from JSON
        author1_json = '{"id":"multi-1","name":"Multi Author 1","email":"multi1@example.com"}'
        author2_json = '{"id":"multi-2","name":"Multi Author 2","email":"multi2@example.com"}'

        json_author1 = Author.from_json(author1_json)
        json_author2 = Author.from_json(author2_json)

        # Create book referencing both
        book_data = {
          "id" => "multi-book",
          "title" => "Multi Author Book",
          "author_ref" => "multi-1",
          "co_authors" => ["multi-1", "multi-2"],
        }

        loaded_book = Book.from_hash(book_data)

        # Users work with actual objects, references are internal
        expect(loaded_book.author_ref).to eq(json_author1)
        expect(loaded_book.co_authors).to contain_exactly(json_author1, json_author2)
      end
    end

    context "when from_* methods process references in data" do
      before do
        Lutaml::Model::Store.clear
        # Pre-load some authors
        Author.from_yaml("id: ref-author-1\nname: Ref Author 1\nemail: ref1@example.com")
        Author.from_json('{"id":"ref-author-2","name":"Ref Author 2","email":"ref2@example.com"}')
      end

      it "from_yaml creates references from string keys in data" do
        book_yaml = <<~YAML
          id: yaml-book
          title: YAML Book
          author_ref: ref-author-1
          co_authors:
            - ref-author-1
            - ref-author-2
        YAML

        loaded_book = Book.from_yaml(book_yaml)

        # Users work with actual objects, references are internal
        expect(loaded_book.author_ref).to be_a(Author)
        expect(loaded_book.author_ref.name).to eq("Ref Author 1")
        expect(loaded_book.co_authors).to all(be_a(Author))
        expect(loaded_book.co_authors.map(&:name)).to contain_exactly("Ref Author 1", "Ref Author 2")
      end

      it "from_json creates references from string keys in data" do
        book_json = {
          "id" => "json-book",
          "title" => "JSON Book",
          "author_ref" => "ref-author-1",
          "co_authors" => ["ref-author-1", "ref-author-2"],
        }.to_json

        loaded_book = Book.from_json(book_json)

        # Users work with actual objects, references are internal
        expect(loaded_book.author_ref).to be_a(Author)
        expect(loaded_book.author_ref.name).to eq("Ref Author 1")
        expect(loaded_book.co_authors).to all(be_a(Author))
        expect(loaded_book.co_authors.map(&:name)).to contain_exactly("Ref Author 1", "Ref Author 2")
      end

      it "from_xml creates references from string keys in data" do
        book_xml = <<~XML
          <book>
            <id>xml-book</id>
            <title>XML Book</title>
            <authorRef>ref-author-1</authorRef>
            <coAuthor>ref-author-1</coAuthor>
            <coAuthor>ref-author-2</coAuthor>
          </book>
        XML

        loaded_book = Book.from_xml(book_xml)

        # Users work with actual objects, references are internal
        expect(loaded_book.author_ref).to be_a(Author)
        expect(loaded_book.author_ref.name).to eq("Ref Author 1")
        expect(loaded_book.co_authors).to all(be_a(Author))
        expect(loaded_book.co_authors.map(&:name)).to contain_exactly("Ref Author 1", "Ref Author 2")
      end

      it "from_hash creates references from string keys in data" do
        book_hash = {
          "id" => "hash-book",
          "title" => "Hash Book",
          "author_ref" => "ref-author-1",
          "co_authors" => ["ref-author-1", "ref-author-2"],
        }

        loaded_book = Book.from_hash(book_hash)

        # Users work with actual objects, references are internal
        expect(loaded_book.author_ref).to be_a(Author)
        expect(loaded_book.author_ref.name).to eq("Ref Author 1")
        expect(loaded_book.co_authors).to all(be_a(Author))
        expect(loaded_book.co_authors.map(&:name)).to contain_exactly("Ref Author 1", "Ref Author 2")
      end
    end
  end

  describe "to_* methods" do
    before do
      Lutaml::Model::Store.clear
      Lutaml::Model::Store.instance.register(first_author)
      Lutaml::Model::Store.instance.register(second_author)

      book.author_ref = "author-1"
      book.co_authors = ["author-1", "author-2"]
    end

    it "to_yaml serializes references as keys" do
      yaml_output = book.to_yaml

      expect(yaml_output).to include("author_ref: author-1")
      expect(yaml_output).to include("co_authors:")
      expect(yaml_output).to include("- author-1")
      expect(yaml_output).to include("- author-2")
      expect(yaml_output).not_to include("#<Lutaml::Model::Type::Reference")
    end

    it "to_json serializes references as keys" do
      json_output = book.to_json
      parsed = JSON.parse(json_output)

      expect(parsed["author_ref"]).to eq("author-1")
      expect(parsed["co_authors"]).to eq(["author-1", "author-2"])
    end

    it "to_xml serializes references as keys" do
      xml_output = book.to_xml

      expect(xml_output).to include("<authorRef>author-1</authorRef>")
      expect(xml_output).to include("<coAuthor>author-1</coAuthor>")
      expect(xml_output).to include("<coAuthor>author-2</coAuthor>")
      expect(xml_output).not_to include("#<Lutaml::Model::Type::Reference")
    end

    it "to_hash serializes references as keys (consistent with other formats)" do
      hash_output = book.to_hash

      # Hash format also serializes to keys, consistent with other formats
      expect(hash_output["author_ref"]).to eq("author-1")
      expect(hash_output["co_authors"]).to eq(["author-1", "author-2"])
    end

    context "when testing round-trip consistency" do
      it "maintains reference integrity through YAML round-trip" do
        yaml_data = book.to_yaml
        reloaded_book = Book.from_yaml(yaml_data)

        # Users work with actual objects, references are internal
        expect(reloaded_book.author_ref.name).to eq("John Doe")
        expect(reloaded_book.co_authors.map(&:name)).to eq(["John Doe", "Jane Smith"])
      end

      it "maintains reference integrity through JSON round-trip" do
        json_data = book.to_json
        reloaded_book = Book.from_json(json_data)

        expect(reloaded_book.author_ref.name).to eq("John Doe")
        expect(reloaded_book.co_authors.map(&:name)).to eq(["John Doe", "Jane Smith"])
      end

      it "maintains reference integrity through XML round-trip" do
        xml_data = book.to_xml
        reloaded_book = Book.from_xml(xml_data)

        expect(reloaded_book.author_ref.name).to eq("John Doe")
        expect(reloaded_book.co_authors.map(&:name)).to eq(["John Doe", "Jane Smith"])
      end

      it "maintains reference integrity through Hash round-trip (with key serialization)" do
        hash_data = book.to_hash
        reloaded_book = Book.from_hash(hash_data)

        # Users work with actual objects, references are internal
        expect(reloaded_book.author_ref).to be_a(Author)
        expect(reloaded_book.author_ref.id).to eq("author-1") # ID is the string key
        expect(reloaded_book.author_ref.name).to eq("John Doe")
        expect(reloaded_book.co_authors.map(&:id)).to eq(["author-1", "author-2"])
        expect(reloaded_book.co_authors.map(&:name)).to eq(["John Doe", "Jane Smith"])
      end
    end
  end

  describe "edge cases in from_*/to_* methods" do
    before { Lutaml::Model::Store.clear }

    it "handles nil references gracefully" do
      book_data = {
        "id" => "nil-book",
        "title" => "Book with Nil Refs",
        "author_ref" => nil,
        "co_authors" => [],
      }

      loaded_book = Book.from_hash(book_data)

      # nil references return nil, not Reference objects
      expect(loaded_book.author_ref).to be_nil
      expect(loaded_book.co_authors).to be_empty
    end

    it "handles missing references gracefully" do
      book_data = {
        "id" => "missing-book",
        "title" => "Book with Missing Refs",
        "author_ref" => "non-existent-author",
        "co_authors" => ["non-existent-author"],
      }

      loaded_book = Book.from_hash(book_data)

      # For missing references, we get nil (reference couldn't resolve)
      expect(loaded_book.author_ref).to be_nil
      expect(loaded_book.co_authors).to eq([nil]) # Still maintains array structure
    end

    it "serializes unresolved references correctly" do
      # Create book with reference to non-existent author
      book.author_ref = "non-existent"

      yaml_output = book.to_yaml
      expect(yaml_output).not_to include("author_ref")

      # Round-trip should preserve the key even if unresolvable
      reloaded_book = Book.from_yaml(yaml_output)
      expect(reloaded_book.author_ref).to be_nil # Unresolvable reference returns nil
    end
  end

  describe "reference key accessor methods" do
    it "generates key accessor methods for single references" do
      book.author_ref = "author-1"

      # Generated method: <attribute>_<key_attribute>
      expect(book).to respond_to(:author_ref_id)
      expect(book.author_ref_id).to eq("author-1")

      # Object resolution still works
      expect(book.author_ref).to be_a(Author)
      expect(book.author_ref.id).to eq("author-1")
    end

    it "generates key accessor methods for collection references with pluralization" do
      book.co_authors = ["author-1", "author-2"]

      # Generated method: <attribute>_<pluralized_key_attribute>
      expect(book).to respond_to(:co_authors_ids)
      expect(book.co_authors_ids).to eq(["author-1", "author-2"])

      # Object resolution still works
      expect(book.co_authors).to all(be_a(Author))
      expect(book.co_authors.map(&:id)).to eq(["author-1", "author-2"])
    end

    it "handles nil and empty references in key accessors" do
      # Nil single reference
      expect(book.author_ref_id).to be_nil

      # Empty collection reference
      expect(book.co_authors_ids).to eq([])

      # Set some values
      book.author_ref = "author-1"
      book.co_authors = ["author-2"]

      expect(book.author_ref_id).to eq("author-1")
      expect(book.co_authors_ids).to eq(["author-2"])
    end

    context "with custom key attributes" do
      let(:category_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :slug, :string
          attribute :name, :string
        end
      end

      let(:product_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string
          attribute :title, :string
          attribute :category_ref, { ref: ["Category", :slug] }
          attribute :tags, { ref: ["Category", :slug] }, collection: true
        end
      end

      before do
        stub_const("Category", category_class)
        stub_const("Product", product_class)
      end

      it "generates methods based on the key attribute, not just id" do
        product = Product.new(id: "prod-1", title: "Test Product")
        product.category_ref = "electronics"
        product.tags = ["electronics", "gadgets"]

        # Generated methods use the key attribute name
        expect(product).to respond_to(:category_ref_slug)
        expect(product).to respond_to(:tags_slugs)

        expect(product.category_ref_slug).to eq("electronics")
        expect(product.tags_slugs).to eq(["electronics", "gadgets"])
      end
    end
  end
end
