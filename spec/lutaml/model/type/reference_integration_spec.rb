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

RSpec.describe "Reference Type Integration" do
  let(:author1) { Author.new(id: "author-1", name: "John Doe", email: "john@example.com") }
  let(:author2) { Author.new(id: "author-2", name: "Jane Smith", email: "jane@example.com") }
  let(:book) { Book.new(id: "book-1", title: "Great Book") }

  before do
    Lutaml::Model::Store.instance.register(author1)
    Lutaml::Model::Store.instance.register(author2)
  end

  after do
    Lutaml::Model::Store.instance.clear
  end

  describe "single reference" do
    it "assigns and resolves correctly" do
      book.author_ref = "author-1"
      
      expect(book.author_ref).to be_a(Lutaml::Model::Type::Reference)
      expect(book.author_ref.key).to eq("author-1")
      expect(book.author_ref.resolve).to eq(author1)
      expect(book.author_ref.resolve.name).to eq("John Doe")
    end
  end

  describe "collection of references" do
    it "assigns and resolves correctly" do
      book.co_authors = ["author-1", "author-2"]
      
      expect(book.co_authors).to all(be_a(Lutaml::Model::Type::Reference))
      expect(book.co_authors.map(&:key)).to eq(["author-1", "author-2"])
      expect(book.co_authors.map(&:resolve)).to eq([author1, author2])
    end
  end

  describe "YAML round-trip" do
    it "serializes to keys and deserializes to references" do
      book.author_ref = "author-1"
      book.co_authors = ["author-1", "author-2"]
      
      yaml_data = book.to_yaml
      expect(yaml_data).to include("author_ref: author-1")
      expect(yaml_data).to include("- author-1")
      expect(yaml_data).to include("- author-2")
      
      loaded_book = Book.from_yaml(yaml_data)
      expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
      expect(loaded_book.author_ref.resolve.name).to eq("John Doe")
      expect(loaded_book.co_authors.map(&:resolve).map(&:name)).to eq(["John Doe", "Jane Smith"])
    end
  end

  describe "JSON round-trip" do
    it "serializes to keys and deserializes to references" do
      book.author_ref = "author-1"
      book.co_authors = ["author-1", "author-2"]
      
      json_data = book.to_json
      parsed = JSON.parse(json_data)
      expect(parsed["author_ref"]).to eq("author-1")
      expect(parsed["co_authors"]).to eq(["author-1", "author-2"])
      
      loaded_book = Book.from_json(json_data)
      expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
      expect(loaded_book.author_ref.resolve.name).to eq("John Doe")
      expect(loaded_book.co_authors.map(&:resolve).map(&:name)).to eq(["John Doe", "Jane Smith"])
    end
  end

  describe "from_* methods" do
    context "objects auto-register during loading" do
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
        ref = Lutaml::Model::Type::Reference.new("Author", :id, "loaded-author")
        expect(ref.resolve).to eq(loaded_author)
        expect(ref.resolve.name).to eq("Loaded Author")
      end
      
      it "from_json loads and auto-registers objects" do
        json_data = '{"id":"json-author","name":"JSON Author","email":"json@example.com"}'
        
        loaded_author = Author.from_json(json_data)
        
        expect(loaded_author.name).to eq("JSON Author")
        expect(loaded_author.id).to eq("json-author")
        
        # Verify auto-registration
        ref = Lutaml::Model::Type::Reference.new("Author", :id, "json-author")
        expect(ref.resolve).to eq(loaded_author)
        expect(ref.resolve.name).to eq("JSON Author")
      end
      
      it "from_xml loads and auto-registers objects" do
        xml_data = "<author><id>xml-author</id><name>XML Author</name><email>xml@example.com</email></author>"
        
        loaded_author = Author.from_xml(xml_data)
        
        expect(loaded_author.name).to eq("XML Author")
        expect(loaded_author.id).to eq("xml-author")
        
        # Verify auto-registration
        ref = Lutaml::Model::Type::Reference.new("Author", :id, "xml-author")
        expect(ref.resolve).to eq(loaded_author)
        expect(ref.resolve.name).to eq("XML Author")
      end
      
      it "from_hash loads and auto-registers objects" do
        hash_data = {
          "id" => "hash-author",
          "name" => "Hash Author", 
          "email" => "hash@example.com"
        }
        
        loaded_author = Author.from_hash(hash_data)
        
        expect(loaded_author.name).to eq("Hash Author")
        expect(loaded_author.id).to eq("hash-author")
        
        # Verify auto-registration
        ref = Lutaml::Model::Type::Reference.new("Author", :id, "hash-author")
        expect(ref.resolve).to eq(loaded_author)
        expect(ref.resolve.name).to eq("Hash Author")
      end
    end
    
    context "references work immediately after loading" do
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
          "co_authors" => ["yaml-author"]
        }.to_json
        
        loaded_book = Book.from_json(book_json)
        
        expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
        expect(loaded_book.author_ref.resolve).to eq(yaml_author)
        expect(loaded_book.author_ref.resolve.name).to eq("YAML Author")
        expect(loaded_book.co_authors.first.resolve).to eq(yaml_author)
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
          "co_authors" => ["multi-1", "multi-2"]
        }
        
        loaded_book = Book.from_hash(book_data)
        
        expect(loaded_book.author_ref.resolve).to eq(json_author1)
        expect(loaded_book.co_authors.map(&:resolve)).to contain_exactly(json_author1, json_author2)
      end
    end
    
    context "from_* methods with references in data" do
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
        
        expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
        expect(loaded_book.author_ref.resolve.name).to eq("Ref Author 1")
        expect(loaded_book.co_authors).to all(be_a(Lutaml::Model::Type::Reference))
        expect(loaded_book.co_authors.map(&:resolve).map(&:name)).to contain_exactly("Ref Author 1", "Ref Author 2")
      end
      
      it "from_json creates references from string keys in data" do
        book_json = {
          "id" => "json-book",
          "title" => "JSON Book",
          "author_ref" => "ref-author-1", 
          "co_authors" => ["ref-author-1", "ref-author-2"]
        }.to_json
        
        loaded_book = Book.from_json(book_json)
        
        expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
        expect(loaded_book.author_ref.resolve.name).to eq("Ref Author 1")
        expect(loaded_book.co_authors).to all(be_a(Lutaml::Model::Type::Reference))
        expect(loaded_book.co_authors.map(&:resolve).map(&:name)).to contain_exactly("Ref Author 1", "Ref Author 2")
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
        
        expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
        expect(loaded_book.author_ref.resolve.name).to eq("Ref Author 1")
        expect(loaded_book.co_authors).to all(be_a(Lutaml::Model::Type::Reference))
        expect(loaded_book.co_authors.map(&:resolve).map(&:name)).to contain_exactly("Ref Author 1", "Ref Author 2")
      end
      
      it "from_hash creates references from string keys in data" do
        book_hash = {
          "id" => "hash-book",
          "title" => "Hash Book",
          "author_ref" => "ref-author-1",
          "co_authors" => ["ref-author-1", "ref-author-2"]
        }
        
        loaded_book = Book.from_hash(book_hash)
        
        expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
        expect(loaded_book.author_ref.resolve.name).to eq("Ref Author 1")
        expect(loaded_book.co_authors).to all(be_a(Lutaml::Model::Type::Reference))
        expect(loaded_book.co_authors.map(&:resolve).map(&:name)).to contain_exactly("Ref Author 1", "Ref Author 2")
      end
    end
  end

  describe "to_* methods" do
    before do
      Lutaml::Model::Store.clear
      Lutaml::Model::Store.instance.register(author1)
      Lutaml::Model::Store.instance.register(author2)
      
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
    
    context "round-trip consistency" do
      it "maintains reference integrity through YAML round-trip" do
        yaml_data = book.to_yaml
        reloaded_book = Book.from_yaml(yaml_data)
        
        expect(reloaded_book.author_ref.resolve.name).to eq("John Doe")
        expect(reloaded_book.co_authors.map(&:resolve).map(&:name)).to eq(["John Doe", "Jane Smith"])
      end
      
      it "maintains reference integrity through JSON round-trip" do
        json_data = book.to_json
        reloaded_book = Book.from_json(json_data)
        
        expect(reloaded_book.author_ref.resolve.name).to eq("John Doe")
        expect(reloaded_book.co_authors.map(&:resolve).map(&:name)).to eq(["John Doe", "Jane Smith"])
      end
      
      it "maintains reference integrity through XML round-trip" do
        xml_data = book.to_xml
        reloaded_book = Book.from_xml(xml_data)
        
        expect(reloaded_book.author_ref.resolve.name).to eq("John Doe")
        expect(reloaded_book.co_authors.map(&:resolve).map(&:name)).to eq(["John Doe", "Jane Smith"])
      end
      
      it "maintains reference integrity through Hash round-trip (with key serialization)" do
        hash_data = book.to_hash
        reloaded_book = Book.from_hash(hash_data)
        
        # Hash serializes to keys like other formats, so references resolve normally
        expect(reloaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
        expect(reloaded_book.author_ref.key).to eq("author-1") # Key is the string key
        expect(reloaded_book.author_ref.resolve.name).to eq("John Doe")
        expect(reloaded_book.co_authors.map(&:key)).to eq(["author-1", "author-2"])
        expect(reloaded_book.co_authors.map(&:resolve).map(&:name)).to eq(["John Doe", "Jane Smith"])
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
        "co_authors" => []
      }
      
      loaded_book = Book.from_hash(book_data)
      
      # nil creates a Reference with nil key, not a nil reference
      expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
      expect(loaded_book.author_ref.key).to be_nil
      expect(loaded_book.author_ref.resolve).to be_nil
      expect(loaded_book.co_authors).to be_empty
    end
    
    it "handles missing references gracefully" do
      book_data = {
        "id" => "missing-book",
        "title" => "Book with Missing Refs",
        "author_ref" => "non-existent-author",
        "co_authors" => ["non-existent-author"]
      }
      
      loaded_book = Book.from_hash(book_data)
      
      expect(loaded_book.author_ref).to be_a(Lutaml::Model::Type::Reference)
      expect(loaded_book.author_ref.resolve).to be_nil
      expect(loaded_book.co_authors.first.resolve).to be_nil
    end
    
    it "serializes unresolved references correctly" do
      # Create book with reference to non-existent author
      book.author_ref = "non-existent"
      
      yaml_output = book.to_yaml
      expect(yaml_output).to include("author_ref: non-existent")
      
      # Round-trip should preserve the key even if unresolvable
      reloaded_book = Book.from_yaml(yaml_output)
      expect(reloaded_book.author_ref.key).to eq("non-existent")
      expect(reloaded_book.author_ref.resolve).to be_nil
    end
  end

  describe "custom key attributes" do
    it "sets up references with correct key attribute" do
      ref = Lutaml::Model::Type::Reference.new("Category", :slug, "electronics")
      
      expect(ref.key_attribute).to eq(:slug)
      expect(ref.key).to eq("electronics")
      expect(ref.model_class).to eq("Category")
    end
  end
end
