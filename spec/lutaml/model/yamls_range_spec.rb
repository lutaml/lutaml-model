require "spec_helper"
require_relative "../../fixtures/yamls_range_concept"

RSpec.describe "YAMLS sequence range positions" do
  # Doc 0-1: Header fields (title/version), Doc 2-3: Entry fields (name/value), Doc 4: Footer fields (note)
  let(:mixed_doc_yaml) do
    <<~YAMLS
      ---
      title: Doc Zero
      version: 0

      ---
      title: Doc One
      version: 1

      ---
      name: Doc Two
      value: v2

      ---
      name: Doc Three
      value: v3

      ---
      note: end of stream
    YAMLS
  end

  # All docs use Entry fields (name/value) for Entry-only models
  let(:entry_doc_yaml) do
    <<~YAMLS
      ---
      name: Doc Zero
      value: v0

      ---
      name: Doc One
      value: v1

      ---
      name: Doc Two
      value: v2

      ---
      name: Doc Three
      value: v3

      ---
      name: Doc Four
      value: v4
    YAMLS
  end

  # All docs use Header fields (title/version) for Header-only models
  let(:header_doc_yaml) do
    <<~YAMLS
      ---
      title: Doc Zero
      version: 0

      ---
      title: Doc One
      version: 1

      ---
      title: Doc Two
      version: 2

      ---
      title: Doc Three
      version: 3

      ---
      title: Doc Four
      version: 4
    YAMLS
  end

  describe "range 0..1, 2..3, and negative -1" do
    subject(:doc) { YamlsRangeTest::Document.from_yamls(mixed_doc_yaml) }

    it "maps documents 0 and 1 to headers collection" do
      expect(doc.headers.length).to eq(2)
      expect(doc.headers[0].title).to eq("Doc Zero")
      expect(doc.headers[0].version).to eq(0)
      expect(doc.headers[1].title).to eq("Doc One")
      expect(doc.headers[1].version).to eq(1)
    end

    it "maps documents 2 and 3 to entries collection" do
      expect(doc.entries.length).to eq(2)
      expect(doc.entries[0].name).to eq("Doc Two")
      expect(doc.entries[0].value).to eq("v2")
      expect(doc.entries[1].name).to eq("Doc Three")
      expect(doc.entries[1].value).to eq("v3")
    end

    it "maps document -1 (last) to footer" do
      expect(doc.footer).to be_a(YamlsRangeTest::Footer)
      expect(doc.footer.note).to eq("end of stream")
    end

    it "round-trips through serialization" do
      output = doc.to_yamls
      doc2 = YamlsRangeTest::Document.from_yamls(output)
      expect(doc2.headers.length).to eq(2)
      expect(doc2.headers[0].title).to eq("Doc Zero")
      expect(doc2.entries.length).to eq(2)
      expect(doc2.entries[0].name).to eq("Doc Two")
      expect(doc2.footer.note).to eq("end of stream")
    end
  end

  describe "negative range -2..-1" do
    subject(:doc) { YamlsRangeTest::DocumentNegRange.from_yamls(mixed_doc_yaml) }

    it "maps documents 0 and 1 to headers" do
      expect(doc.headers.length).to eq(2)
      expect(doc.headers[0].title).to eq("Doc Zero")
      expect(doc.headers[1].title).to eq("Doc One")
    end

    it "maps documents -2..-1 (docs 3 and 4) to trailers" do
      expect(doc.trailers.length).to eq(2)
      expect(doc.trailers[0].name).to eq("Doc Three")
      expect(doc.trailers[0].value).to eq("v3")
      # Doc 4 has 'note' not 'name'/'value', so Entry fields are nil
      expect(doc.trailers[1].name).to be_nil
      expect(doc.trailers[1].value).to be_nil
    end

    it "round-trips through serialization" do
      output = doc.to_yamls
      doc2 = YamlsRangeTest::DocumentNegRange.from_yamls(output)
      expect(doc2.headers.length).to eq(2)
      expect(doc2.trailers.length).to eq(2)
      expect(doc2.trailers[0].name).to eq("Doc Three")
    end
  end

  describe "range 1..-1 (from position 1 to end)" do
    # Doc 0 is Header (title/version), docs 1-4 are Entry (name/value)
    let(:open_range_yaml) do
      <<~YAMLS
        ---
        title: Doc Zero
        version: 0

        ---
        name: Doc One
        value: v1

        ---
        name: Doc Two
        value: v2

        ---
        name: Doc Three
        value: v3

        ---
        name: Doc Four
        value: v4
      YAMLS
    end

    subject(:doc) { YamlsRangeTest::DocumentOpenRange.from_yamls(open_range_yaml) }

    it "maps document 0 to header" do
      expect(doc.header.title).to eq("Doc Zero")
      expect(doc.header.version).to eq(0)
    end

    it "maps documents 1..-1 (all remaining) to rest collection" do
      expect(doc.rest.length).to eq(4)
      expect(doc.rest[0].name).to eq("Doc One")
      expect(doc.rest[0].value).to eq("v1")
      expect(doc.rest[1].name).to eq("Doc Two")
      expect(doc.rest[2].name).to eq("Doc Three")
      expect(doc.rest[3].name).to eq("Doc Four")
    end

    it "round-trips through serialization" do
      output = doc.to_yamls
      doc2 = YamlsRangeTest::DocumentOpenRange.from_yamls(output)
      expect(doc2.header.title).to eq("Doc Zero")
      expect(doc2.rest.length).to eq(4)
      expect(doc2.rest[0].name).to eq("Doc One")
    end
  end

  describe "negative single index -1" do
    subject(:doc) { YamlsRangeTest::DocumentLastOnly.from_yamls(entry_doc_yaml) }

    it "maps only the last document" do
      expect(doc.last_entry).to be_a(YamlsRangeTest::Entry)
      expect(doc.last_entry.name).to eq("Doc Four")
      expect(doc.last_entry.value).to eq("v4")
    end

    it "round-trips through serialization" do
      output = doc.to_yamls
      doc2 = YamlsRangeTest::DocumentLastOnly.from_yamls(output)
      expect(doc2.last_entry.name).to eq("Doc Four")
    end
  end

  describe "YamlsSequenceRule#resolve_range" do
    let(:rule_class) { Lutaml::Yamls::Adapter::YamlsSequenceRule }

    it "resolves Integer 0 to 0..0" do
      rule = rule_class.new(0, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(0..0)
    end

    it "resolves Integer -1 to 4..4 when doc_count is 5" do
      rule = rule_class.new(-1, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(4..4)
    end

    it "resolves Integer -2 to 3..3 when doc_count is 5" do
      rule = rule_class.new(-2, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(3..3)
    end

    it "resolves Range 0..1 to 0..1" do
      rule = rule_class.new(0..1, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(0..1)
    end

    it "resolves Range -2..-1 to 3..4 when doc_count is 5" do
      rule = rule_class.new(-2..-1, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(3..4)
    end

    it "resolves Range 1.. to 1..4 when doc_count is 5" do
      rule = rule_class.new(1.., to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(1..4)
    end

    it "resolves Range 2..-1 to 2..4 when doc_count is 5" do
      rule = rule_class.new(2..-1, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(2..4)
    end

    it "resolves Range -3..-1 to 2..4 when doc_count is 5" do
      rule = rule_class.new(-3..-1, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(2..4)
    end

    it "clamps out-of-bounds end index" do
      rule = rule_class.new(3..10, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(3..4)
    end

    it "clamps negative start that resolves below 0" do
      rule = rule_class.new(-10..-1, to: :x, type: Object)
      expect(rule.resolve_range(5)).to eq(0..4)
    end

    it "returns nil for zero doc_count" do
      rule = rule_class.new(0, to: :x, type: Object)
      expect(rule.resolve_range(0)).to be_nil
    end
  end

  # --- 3-range tests with 3 different class types ---

  # 7-doc YAML: docs 0-1 = Header, docs 2-3 = Metadata, docs 4-5 = Entry, doc 6 = Footer
  let(:seven_doc_yaml) do
    <<~YAMLS
      ---
      title: Alpha
      version: 1

      ---
      title: Beta
      version: 2

      ---
      author: Alice
      date: 2024-01-01

      ---
      author: Bob
      date: 2024-06-15

      ---
      name: EntryOne
      value: val1

      ---
      name: EntryTwo
      value: val2

      ---
      note: final note
    YAMLS
  end

  describe "3 ranges: 0..1 (Header), 2..3 (Metadata), -2..-1 (Entry) — flex range at back" do
    subject(:doc) { YamlsRangeTest::ThreeRangesFrontFlex.from_yamls(seven_doc_yaml) }

    it "maps docs 0..1 to headers" do
      expect(doc.headers.length).to eq(2)
      expect(doc.headers[0].title).to eq("Alpha")
      expect(doc.headers[1].title).to eq("Beta")
    end

    it "maps docs 2..3 to metas" do
      expect(doc.metas.length).to eq(2)
      expect(doc.metas[0].author).to eq("Alice")
      expect(doc.metas[1].author).to eq("Bob")
    end

    it "maps docs -2..-1 (docs 5 and 6) to trailers" do
      expect(doc.trailers.length).to eq(2)
      expect(doc.trailers[0].name).to eq("EntryTwo")
      expect(doc.trailers[0].value).to eq("val2")
      # doc 6 has 'note' field, not 'name'/'value', so Entry fields are nil
      expect(doc.trailers[1].name).to be_nil
    end

    it "round-trips through serialization" do
      output = doc.to_yamls
      doc2 = YamlsRangeTest::ThreeRangesFrontFlex.from_yamls(output)
      expect(doc2.headers.length).to eq(2)
      expect(doc2.metas.length).to eq(2)
      expect(doc2.trailers.length).to eq(2)
      expect(doc2.metas[0].author).to eq("Alice")
    end
  end

  describe "3 ranges: 0 (Header), 1..3 (Metadata), -1 (Footer) — mixed single and range" do
    subject(:doc) { YamlsRangeTest::ThreeRangesMixed.from_yamls(seven_doc_yaml) }

    it "maps doc 0 to header" do
      expect(doc.header.title).to eq("Alpha")
      expect(doc.header.version).to eq(1)
    end

    it "maps docs 1..3 to metas" do
      expect(doc.metas.length).to eq(3)
      # doc 1 has Header fields (title/version), mapped as Metadata → author is nil
      expect(doc.metas[0].author).to be_nil
      expect(doc.metas[1].author).to eq("Alice")
      expect(doc.metas[2].author).to eq("Bob")
    end

    it "maps doc -1 (last) to footer" do
      expect(doc.footer.note).to eq("final note")
    end

    it "round-trips through serialization" do
      output = doc.to_yamls
      doc2 = YamlsRangeTest::ThreeRangesMixed.from_yamls(output)
      expect(doc2.header.title).to eq("Alpha")
      expect(doc2.metas.length).to eq(3)
      expect(doc2.footer.note).to eq("final note")
    end
  end

  describe "3 ranges: 0..1 (Header), -3..-2 (Entry), -1 (Footer) — negative middle range" do
    subject(:doc) { YamlsRangeTest::ThreeRangesNegMiddle.from_yamls(seven_doc_yaml) }

    it "maps docs 0..1 to headers" do
      expect(doc.headers.length).to eq(2)
      expect(doc.headers[0].title).to eq("Alpha")
      expect(doc.headers[1].title).to eq("Beta")
    end

    it "maps docs -3..-2 (docs 4 and 5) to entries" do
      expect(doc.entries.length).to eq(2)
      expect(doc.entries[0].name).to eq("EntryOne")
      expect(doc.entries[0].value).to eq("val1")
      expect(doc.entries[1].name).to eq("EntryTwo")
      expect(doc.entries[1].value).to eq("val2")
    end

    it "maps doc -1 (last) to footer" do
      expect(doc.footer.note).to eq("final note")
    end

    it "round-trips through serialization" do
      output = doc.to_yamls
      doc2 = YamlsRangeTest::ThreeRangesNegMiddle.from_yamls(output)
      expect(doc2.headers.length).to eq(2)
      expect(doc2.entries.length).to eq(2)
      expect(doc2.entries[0].name).to eq("EntryOne")
      expect(doc2.footer.note).to eq("final note")
    end
  end
end
