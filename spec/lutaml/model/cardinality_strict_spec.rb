require "spec_helper"
require_relative "../../../lib/lutaml/model"

module CardinalityStrictSpec
  # Singular attribute only, mapped for every format.
  class Simple < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      root "simple"
      map_element "name", to: :name
    end

    # key_value covers JSON, YAML and TOML
    key_value do
      map "name", to: :name
    end
  end

  # Bounded collection, mapped for every format.
  class Ranged < Lutaml::Model::Serializable
    attribute :nick, :string, collection: 0..2

    xml do
      root "ranged"
      map_element "nick", to: :nick
    end

    key_value do
      map "nick", to: :nick
    end
  end

  # Singular attribute deserialized by a custom method. The method receives one
  # node for a single occurrence and the whole array when several arrive — the
  # same shape a custom `to:` method already gets for a collection. It records
  # what it saw so the specs can assert the handover.
  class CustomSingular < Lutaml::Model::Serializable
    attribute :label, :string

    xml do
      root "custom_singular"
      map_element "label", to: :label,
                           with: { from: :label_from, to: :label_to }
    end

    def self.received
      @received ||= []
    end

    def label_from(model, node)
      self.class.received << node
      texts = Array(node).map { |n| n.text.upcase }
      model.label = texts.size > 1 ? texts : texts.first
    end

    def label_to(model, parent, doc); end
  end

  # A transform on the same rule as a custom deserializer. The transformer runs
  # first and sees whatever arrived, including the over-count array.
  class RecordingTransform < Lutaml::Model::ValueTransformer
    def self.seen
      @seen ||= []
    end

    def from_xml(value)
      self.class.seen << value
      value
    end

    def to_xml
      value
    end
  end

  class CustomWithTransform < Lutaml::Model::Serializable
    attribute :label, :string

    xml do
      root "custom_with_transform"
      map_element "label", to: :label,
                           with: { from: :label_from, to: :label_to },
                           transform: RecordingTransform
    end

    def label_from(model, node)
      model.label = Array(node).map { |n| n.text.upcase }
    end

    def label_to(model, parent, doc); end
  end

  # Singular :hash attribute. Shares the same parse branch as custom methods,
  # without a custom method of its own.
  class HashSingular < Lutaml::Model::Serializable
    attribute :meta, :hash

    xml do
      root "hash_singular"
      map_element "meta", to: :meta
    end
  end

  # A custom method that collapses the array to one value. The over-count is
  # then not reported: the method decided what the attribute holds.
  class CollapsingCustom < Lutaml::Model::Serializable
    attribute :label, :string

    xml do
      root "collapsing_custom"
      map_element "label", to: :label,
                           with: { from: :label_from, to: :label_to }
    end

    def label_from(model, node)
      model.label = Array(node).first.text.upcase
    end

    def label_to(model, parent, doc); end
  end

  # Singular attribute with an enum. The generated reader used to collapse the
  # stored array via .first, which hid an over-count from #validate entirely.
  class EnumSingular < Lutaml::Model::Serializable
    attribute :kind, :string, values: %w[a b]

    key_value do
      map "kind", to: :kind
    end
  end

  # Enum on a bounded collection: the case where both the range and the value
  # set can fail at once.
  class EnumRanged < Lutaml::Model::Serializable
    attribute :kind, :string, values: %w[a b], collection: 0..2

    xml do
      root "enum_ranged"
      map_element "kind", to: :kind
    end
  end

  # Enum and pattern on collections, to pin that both skip nil elements.
  class NilElements < Lutaml::Model::Serializable
    attribute :kind, :string, values: %w[a b], collection: true
    attribute :code, :string, pattern: /\A[a-z]+\z/, collection: true

    key_value do
      map "kind", to: :kind
      map "code", to: :code
    end
  end

  # A value-level validation that measures length. Stands in for the facets
  # PR #719 adds: it must never run against an over-count array, or a
  # `min_length` check would silently measure the element count instead.
  class LengthChecked < Lutaml::Model::Serializable
    attribute :code, :string, validations: proc {
      validate :code_length

      def code_length(value)
        errors.add(:code, "measured #{value.length}")
      end
    }

    key_value do
      map "code", to: :code
    end
  end

  # A plain Ruby class mapped with `model`. Instances have no #validate, so a
  # cardinality violation has nowhere to be reported later.
  class PlainTarget
    attr_accessor :name
  end

  class PlainMapper < Lutaml::Model::Serializable
    model PlainTarget

    attribute :name, :string

    xml do
      root "plain"
      map_element "name", to: :name
    end

    key_value do
      map "name", to: :name
    end
  end
end

# #185 asks for cardinality enforcement across XML AND key/value formats.
# Parsing preserves whatever multiplicity arrived; `.validate` judges it. An
# over-count on a singular attribute is reported there, not raised at parse.
# Declared ranges keep their existing parse-time timing.
RSpec.describe "Issue #185 strict cardinality" do
  describe "non-collection attribute (default 0..1) given more than one value" do
    it "does not raise at parse for XML; reports on validate" do
      obj = nil
      expect do
        obj = CardinalityStrictSpec::Simple.from_xml(
          "<simple><name>A</name><name>B</name></simple>",
        )
      end.not_to raise_error

      expect(obj.name).to eq(%w[A B])
      expect(obj.validate).to include(
        an_instance_of(Lutaml::Model::CollectionTrueMissingError),
      )
      expect { obj.validate! }.to raise_error(Lutaml::Model::ValidationError)
    end

    {
      json: ['{"name":["A","B"]}', '{"name":"A"}'],
      yaml: ["name:\n- A\n- B\n", "name: A\n"],
      toml: ['name = ["A", "B"]', 'name = "A"'],
    }.each do |format, (over_count, single)|
      it "does not raise at parse for #{format.upcase}; reports on validate" do
        obj = nil
        expect do
          obj = CardinalityStrictSpec::Simple.public_send(:"from_#{format}",
                                                          over_count)
        end.not_to raise_error

        expect(obj.name).to eq(%w[A B])
        expect(obj.validate).to include(
          an_instance_of(Lutaml::Model::CollectionTrueMissingError),
        )
      end

      it "accepts a single #{format.upcase} value" do
        obj = CardinalityStrictSpec::Simple.public_send(:"from_#{format}",
                                                        single)
        expect(obj.name).to eq("A")
        expect(obj.validate).to be_empty
      end
    end

    it "accepts a single XML occurrence as a scalar" do
      obj = CardinalityStrictSpec::Simple.from_xml("<simple><name>A</name></simple>")
      expect(obj.name).to eq("A")
    end

    it "accepts zero XML occurrences" do
      obj = CardinalityStrictSpec::Simple.from_xml("<simple/>")
      expect(obj.name).to be_nil
    end

    context "when the singular attribute uses a custom deserializer" do
      before { CardinalityStrictSpec::CustomSingular.received.clear }

      it "hands the whole array to the custom method for multiple elements" do
        obj = nil
        expect do
          obj = CardinalityStrictSpec::CustomSingular.from_xml(
            "<custom_singular><label>a</label><label>b</label>" \
            "</custom_singular>",
          )
        end.not_to raise_error

        # Invoked once with the whole array, not once per child.
        received = CardinalityStrictSpec::CustomSingular.received
        expect(received.size).to eq(1)
        expect(received.first).to be_a(Array)

        expect(obj.label).to eq(%w[A B])
        expect(obj.validate).to include(
          an_instance_of(Lutaml::Model::CollectionTrueMissingError),
        )
      end

      it "runs the custom method for a single XML element" do
        obj = CardinalityStrictSpec::CustomSingular.from_xml(
          "<custom_singular><label>hi</label></custom_singular>",
        )

        received = CardinalityStrictSpec::CustomSingular.received
        expect(received.size).to eq(1)
        expect(received.first).not_to be_a(Array)

        expect(obj.label).to eq("HI")
        expect(obj.validate).to be_empty
      end
    end

    context "when a transform shares the rule with a custom deserializer" do
      before { CardinalityStrictSpec::RecordingTransform.seen.clear }

      it "runs the transform before the custom method, on the whole array" do
        obj = CardinalityStrictSpec::CustomWithTransform.from_xml(
          "<custom_with_transform><label>a</label><label>b</label>" \
          "</custom_with_transform>",
        )

        seen = CardinalityStrictSpec::RecordingTransform.seen
        expect(seen.size).to eq(1)
        expect(seen.first).to be_a(Array)

        expect(obj.label).to eq(%w[A B])
        expect(obj.validate).to include(
          an_instance_of(Lutaml::Model::CollectionTrueMissingError),
        )
      end
    end

    context "when the custom method collapses the array" do
      it "reports nothing, because the method decided what is stored" do
        obj = CardinalityStrictSpec::CollapsingCustom.from_xml(
          "<collapsing_custom><label>a</label><label>b</label>" \
          "</collapsing_custom>",
        )

        expect(obj.label).to eq("A")
        expect(obj.validate).to be_empty
      end
    end

    context "when the model is a plain Ruby class" do
      # A PORO has no #validate, so deferring would discard the violation.
      # These stay eager for that reason, not by oversight.
      it "raises at parse for XML" do
        expect do
          CardinalityStrictSpec::PlainMapper.from_xml(
            "<plain><name>A</name><name>B</name></plain>",
          )
        end.to raise_error(Lutaml::Model::CollectionTrueMissingError, /`name`/)
      end

      it "raises at parse for key/value" do
        expect do
          CardinalityStrictSpec::PlainMapper.from_json('{"name":["A","B"]}')
        end.to raise_error(Lutaml::Model::CollectionTrueMissingError, /`name`/)
      end

      it "still accepts a single value" do
        obj = CardinalityStrictSpec::PlainMapper.from_xml(
          "<plain><name>A</name></plain>",
        )
        expect(obj).to be_a(CardinalityStrictSpec::PlainTarget)
        expect(obj.name).to eq("A")
      end
    end

    context "when the singular attribute is a :hash" do
      it "keeps a single occurrence a Hash" do
        obj = CardinalityStrictSpec::HashSingular.from_xml(
          "<hash_singular><meta><k>v</k></meta></hash_singular>",
        )
        expect(obj.meta).to eq({ "k" => "v" })
        expect(obj.validate).to be_empty
      end

      it "stores an over-count as an array and reports it on validate" do
        obj = CardinalityStrictSpec::HashSingular.from_xml(
          "<hash_singular><meta><k>v1</k></meta><meta><k>v2</k></meta>" \
          "</hash_singular>",
        )
        expect(obj.meta).to eq([{ "k" => "v1" }, { "k" => "v2" }])
        expect(obj.validate).to include(
          an_instance_of(Lutaml::Model::CollectionTrueMissingError),
        )
      end
    end
  end

  describe "declared collection range (collection: 0..2)" do
    it "flags an XML over-max on validate (XML validates ranges lazily)" do
      obj = nil
      expect do
        obj = CardinalityStrictSpec::Ranged.from_xml(
          "<ranged><nick>a</nick><nick>b</nick><nick>c</nick></ranged>",
        )
      end.not_to raise_error
      expect(obj.validate).to include(
        an_instance_of(Lutaml::Model::CollectionCountOutOfRangeError),
      )
    end

    it "raises a key/value over-max at parse" do
      expect do
        CardinalityStrictSpec::Ranged.from_json('{"nick":["a","b","c"]}')
      end.to raise_error(Lutaml::Model::CollectionCountOutOfRangeError)
    end

    it "accepts values within range for XML and key/value" do
      xml_obj = CardinalityStrictSpec::Ranged.from_xml(
        "<ranged><nick>a</nick><nick>b</nick></ranged>",
      )
      json_obj = CardinalityStrictSpec::Ranged.from_json('{"nick":["a","b"]}')
      expect(xml_obj.validate).to be_empty
      expect(json_obj.validate).to be_empty
    end
  end

  describe "absent optional collection (regression: min-side false positive)" do
    # collection: 0..2 with zero occurrences is valid; it must not raise at
    # key/value parse just because an absent value arrives as nil.
    it "does not raise for an absent optional collection in JSON" do
      obj = nil
      expect { obj = CardinalityStrictSpec::Ranged.from_json("{}") }
        .not_to raise_error
      expect(obj.validate).to be_empty
    end

    it "does not raise for an absent optional collection in YAML" do
      expect { CardinalityStrictSpec::Ranged.from_yaml("--- {}\n") }
        .not_to raise_error
    end

    it "still raises when the range requires a minimum (1..)" do
      klass = Class.new(Lutaml::Model::Serializable) do
        def self.name = "CardinalityStrictSpec::AtLeastOne"
        attribute :nick, :string, collection: (1..)
        key_value { map "nick", to: :nick }
      end
      expect { klass.from_json("{}") }
        .to raise_error(Lutaml::Model::CollectionCountOutOfRangeError)
    end
  end

  describe "map_content is left unchanged" do
    let(:mixed) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name = "CardinalityStrictSpec::Mixed"
        attribute :bold, :string, collection: true
        attribute :content, :string
        xml do
          root "r"
          map_element "bold", to: :bold
          map_content to: :content
        end
      end
    end

    it "does not raise at parse; flags a singular content target on validate" do
      obj = nil
      expect do
        obj = mixed.from_xml(
          "<r>one <bold>b</bold> two <bold>c</bold> three</r>",
        )
      end.not_to raise_error
      expect(obj.validate).to include(
        an_instance_of(Lutaml::Model::CollectionTrueMissingError),
      )
    end
  end

  describe "enum on a singular attribute" do
    it "reports an over-count whose elements are outside the value set" do
      obj = CardinalityStrictSpec::EnumSingular.from_json(
        '{"kind":["a","z"]}',
      )

      expect(obj.kind).to eq(%w[a z])
      expect(obj.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::CollectionTrueMissingError),
      )
    end

    it "reports an over-count whose elements are all in the value set" do
      obj = CardinalityStrictSpec::EnumSingular.from_json(
        '{"kind":["a","b"]}',
      )

      expect(obj.kind).to eq(%w[a b])
      expect(obj.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::CollectionTrueMissingError),
      )
    end

    it "leaves a single value reading as a scalar" do
      obj = CardinalityStrictSpec::EnumSingular.from_json('{"kind":"a"}')

      expect(obj.kind).to eq("a")
      expect(obj.validate).to be_empty
    end

    it "still rejects a single value outside the set" do
      obj = CardinalityStrictSpec::EnumSingular.from_json('{"kind":"z"}')

      expect(obj.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::InvalidValueError),
      )
    end

    # The generated `a?` shorthand reads through the same reader. An attribute
    # holding two values has no honest "yes" to give.
    it "answers the value shorthand false while over-counted" do
      obj = CardinalityStrictSpec::EnumSingular.from_json(
        '{"kind":["a","z"]}',
      )

      expect(obj.a?).to be(false)

      obj.kind = "a"
      expect(obj.a?).to be(true)
    end

    # Known limitation, pinned so it stays visible. An enum setter always
    # stores its value as an array, so a one-element array and a bare scalar
    # are indistinguishable by the time #validate reads the slot. The
    # shape-based rule therefore catches over-counts on an enum but not a
    # one-element array, which a non-enum attribute does flag. Closing this
    # needs the enum setter to preserve the assigned shape.
    it "does not flag a one-element array, unlike a non-enum attribute" do
      enumed = CardinalityStrictSpec::EnumSingular.from_json('{"kind":["a"]}')
      plain = CardinalityStrictSpec::Simple.from_json('{"name":["A"]}')

      expect(enumed.kind).to eq("a")
      expect(enumed.validate).to be_empty

      expect(plain.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::CollectionTrueMissingError),
      )
    end

    # An invalid document does not round-trip. The array reaches the writer as
    # the attribute's value and gets stringified, which is what any singular
    # attribute holding an over-count already does — this is not specific to
    # enums. Pinned so the shape is a visible decision. Fixing the violation
    # restores clean output.
    it "does not round-trip an over-count" do
      obj = CardinalityStrictSpec::EnumSingular.from_json(
        '{"kind":["a","b"]}',
      )

      expect(obj.to_json).to eq('{"kind":"[\"a\", \"b\"]"}')

      obj.kind = "a"
      expect(obj.to_json).to eq('{"kind":"a"}')
    end
  end

  describe "enum on a bounded collection" do
    # Shape before contents: the count is the more fundamental violation, so a
    # value failing both its range and its value set reports the range.
    it "reports the range when both the range and the value set fail" do
      obj = CardinalityStrictSpec::EnumRanged.from_xml(
        "<enum_ranged><kind>a</kind><kind>z</kind><kind>q</kind></enum_ranged>",
      )

      expect(obj.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::CollectionCountOutOfRangeError),
      )
    end

    it "reports the value set when only the value set fails" do
      obj = CardinalityStrictSpec::EnumRanged.from_xml(
        "<enum_ranged><kind>a</kind><kind>z</kind></enum_ranged>",
      )

      expect(obj.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::InvalidValueError),
      )
    end
  end

  describe "nil elements in a collection" do
    it "skips them for both enum and pattern checks" do
      obj = CardinalityStrictSpec::NilElements.from_json(
        '{"kind":["a",null],"code":["ab",null]}',
      )

      expect(obj.validate).to be_empty
    end

    it "still reports a non-nil element outside the value set" do
      obj = CardinalityStrictSpec::NilElements.from_json(
        '{"kind":["a",null,"z"]}',
      )

      expect(obj.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::InvalidValueError),
      )
    end
  end

  describe "a one-element array on a singular attribute" do
    # The rule is about shape, not count: the attribute is declared to hold a
    # value, and an array of one is still an array.
    it "is a violation even though only one value arrived" do
      obj = CardinalityStrictSpec::Simple.from_json('{"name":["A"]}')

      expect(obj.name).to eq(["A"])
      expect(obj.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::CollectionTrueMissingError),
      )
    end
  end

  describe "value-level validations against an over-count (PR #719 guard)" do
    it "does not run them, so nothing measures the element count" do
      obj = CardinalityStrictSpec::LengthChecked.from_json(
        '{"code":["abcd","efgh"]}',
      )

      expect(obj.validate).to contain_exactly(
        an_instance_of(Lutaml::Model::CollectionTrueMissingError),
      )
    end

    it "runs them normally for a single value" do
      obj = CardinalityStrictSpec::LengthChecked.from_json('{"code":"abcd"}')

      expect(obj.validate.map(&:message).join).to include("measured 4")
    end
  end
end
