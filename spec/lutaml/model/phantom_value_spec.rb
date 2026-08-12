# frozen_string_literal: true

require "spec_helper"

# An attribute whose type defines its own `self.cast` used to gain a value
# nobody wrote.
#
# The pipeline hands an attribute "no data arrived" — nil, or the uninitialized
# sentinel — and casts it anyway. Every built-in type returns that input
# unchanged, so nothing showed. A custom `self.cast` returns a real instance,
# and that instance became a value the source never carried: a phantom element
# in the document, or a one-item collection nobody created.
#
# There are more ways to reach a cast than the four reader shapes
# define_attribute_methods dispatches on, so each shape gets its own example
# here, plus a built-in-typed control that must stay clean either way.
module PhantomValueSpec
  # The differentiator: a type with its own cast that manufactures an instance
  # for anything, including nil and the sentinel.
  class Eager < Lutaml::Model::Type::Value
    # Value#initialize casts what it is given, so a cast that constructs would
    # recurse forever. Store the value straight, the way a Serializable-typed
    # element (the shape this bug was found on) does.
    def initialize(value) # rubocop:disable Lint/MissingSuper -- see above
      @value = value
    end

    def self.cast(value)
      return value if value.is_a?(Eager)

      new("E(#{value.inspect})")
    end

    def self.serialize(value)
      value.is_a?(Eager) ? value.value.to_s : value.to_s
    end

    def to_s
      value.to_s
    end
  end

  # S1 / S1c — enum scalar.
  class EnumScalar < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :role, Eager, values: %w[a b]

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "role", to: :role
    end

    key_value do
      map "lead", to: :lead
      map "role", to: :role
    end
  end

  class EnumScalarBuiltIn < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :role, :string, values: %w[a b]

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "role", to: :role
    end

    key_value do
      map "lead", to: :lead
      map "role", to: :role
    end
  end

  # S2 / S2c — enum collection.
  class EnumCollection < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :roles, Eager, values: %w[a b], collection: true

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "roles", to: :roles
    end

    key_value do
      map "lead", to: :lead
      map "roles", to: :roles
    end
  end

  class EnumCollectionBuiltIn < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :roles, :string, values: %w[a b c], collection: true

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "roles", to: :roles
    end
  end

  # S3 — enum whose reader the model already defines.
  class EnumPredefinedReader < Lutaml::Model::Serializable
    def role
      "mine"
    end

    attribute :lead, :string
    attribute :role, Eager, values: %w[a b]

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "role", to: :role
    end
  end

  # S4 — enum with non-String values, so no shorthand methods are generated.
  class EnumNonString < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :level, :integer, values: [1, 2]

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "level", to: :level
    end

    key_value do
      map "lead", to: :lead
      map "level", to: :level
    end
  end

  # S5 — derived scalar, name != method_name. The reader casts on every call.
  class DerivedScalar < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :thing, Eager, method: :source_thing

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "thing", to: :thing
    end

    key_value do
      map "lead", to: :lead
      map "thing", to: :thing
    end

    def source_thing
      nil
    end
  end

  class DerivedScalarWithValue < DerivedScalar
    def source_thing
      "real"
    end
  end

  # S6 — derived collection.
  class DerivedCollection < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :things, Eager, method: :source_things, collection: true

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "things", to: :things
    end

    key_value do
      map "lead", to: :lead
      map "things", to: :things
    end

    def source_things
      nil
    end
  end

  class DerivedCollectionWithValues < DerivedCollection
    def source_things
      %w[x y]
    end
  end

  # S6b — a derived collection whose source method returns one bare value
  # rather than a list. This is the only path that reaches the collection
  # wrap in cast_derived; an Array source goes through cast_value instead.
  class DerivedCollectionScalarSource < DerivedCollection
    def source_things
      "x"
    end
  end

  # S6c — a derived collection that declares its own collection class. An
  # ordinary Array source is a list of elements here too, but
  # collection_instance? only recognises the declared class.
  class EagerCollection < Lutaml::Model::Collection
    instances :items, Eager
  end

  class DerivedCustomCollection < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :things, Eager, collection: EagerCollection,
                              method: :source_things

    def source_things
      %w[x y]
    end
  end

  # S7 — derived where name == method_name, so the branch predicate is false
  # and the regular generator runs instead.
  class DerivedSameName < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :thing, Eager, method: :thing

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "thing", to: :thing
    end
  end

  # S8 — derived whose reader is already defined, so nothing is generated.
  class DerivedPredefinedReader < Lutaml::Model::Serializable
    def thing
      "mine"
    end

    attribute :lead, :string
    attribute :thing, Eager, method: :source_thing

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "thing", to: :thing
    end

    def source_thing
      nil
    end
  end

  # S9 / S10 — Reference attributes. cast_element short-circuits into
  # cast_with_metadata before the type check, so these fabricate with a
  # built-in type too.
  class ReferenceScalar < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :thing, Lutaml::Model::Type::Reference,
              ref_model_class: "PhantomValueSpec::Target",
              ref_key_attribute: :id

    xml do
      root "r"
      map_element "lead", to: :lead
    end
  end

  class ReferenceCollection < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :things, Lutaml::Model::Type::Reference,
              ref_model_class: "PhantomValueSpec::Target",
              ref_key_attribute: :id, collection: true

    xml do
      root "r"
      map_element "lead", to: :lead
    end
  end

  # S11 — regular scalar.
  class RegularScalar < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :thing, Eager

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "thing", to: :thing
    end

    key_value do
      map "lead", to: :lead
      map "thing", to: :thing
    end
  end

  # S12 — regular collection, custom element type. The shape the downstream
  # phantom <w:t/> came from.
  class RegularCollection < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :things, Eager, collection: true

    xml do
      root "r"
      ordered
      map_element "lead", to: :lead
      map_element "things", to: :things
    end

    key_value do
      map "lead", to: :lead
      map "things", to: :things
    end
  end

  # Same shape without `ordered`, because rounds 1 and 2 both mistook this for
  # an ordering problem.
  class RegularCollectionUnordered < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :things, Eager, collection: true

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "things", to: :things
    end
  end

  # S12b — the control. Identical but for the element type.
  class RegularCollectionBuiltIn < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :things, :string, collection: true

    xml do
      root "r"
      ordered
      map_element "lead", to: :lead
      map_element "things", to: :things
    end

    key_value do
      map "lead", to: :lead
      map "things", to: :things
    end
  end

  # S13 — regular attribute whose writer the model already defines. The value
  # is cast before it reaches that writer, so a phantom can be laundered
  # through third-party code.
  class RegularPredefinedWriter < Lutaml::Model::Serializable
    def thing=(value)
      @thing = "seen(#{value.inspect})"
    end

    attribute :lead, :string
    attribute :thing, Eager

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "thing", to: :thing
    end
  end

  # S14 — regular attribute whose name collides with an enum value string, so
  # the writer is regenerated even though a setter already exists.
  class RegularEnumShorthandCollision < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :align, :string, values: %w[char left]
    attribute :char, Eager

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "align", to: :align
      map_element "char", to: :char
    end
  end

  # S17 — regular collection with a custom Collection class.
  class ThingCollection < Lutaml::Model::Collection
    instances :items, Eager
  end

  class RegularCustomCollection < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :things, Eager, collection: ThingCollection

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "things", to: :things
    end
  end

  # S18 — a collection with a real default. The fix must not eat these.
  class SeededCollection < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :things, Eager, collection: true, default: -> { ["seed"] }

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "things", to: :things
    end
  end

  # S20 — a scalar default the mapping asks for explicitly.
  class RenderedDefault < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :thing, Eager, default: -> { "dflt" }

    xml do
      root "r"
      map_element "lead", to: :lead
      map_element "thing", to: :thing, render_default: true
    end
  end
end

RSpec.describe "a value nobody wrote" do
  def compact(xml)
    xml.to_s.gsub(/<\?xml[^>]*\?>/, "").gsub(/\s*\n\s*/, "").strip
  end

  let(:register) { Lutaml::Model::Config.default_register }
  let(:uninitialized) { Lutaml::Model::UninitializedClass.instance }
  let(:bare_xml) { "<r><lead>L</lead></r>" }
  let(:bare_json) { '{"lead":"L"}' }

  # Each format is asserted against its own output. A single combined
  # assertion would hide the shapes where the formats disagree.
  def emits_nothing_extra(klass, attr_name)
    aggregate_failures do
      expect(compact(klass.new(lead: "L").to_xml)).to eq("<r><lead>L</lead></r>")
      expect(klass.new(lead: "L").to_json).to eq('{"lead":"L"}')
      expect(klass.new(lead: "L").to_yaml).to eq("---\nlead: L\n")
      expect(compact(klass.from_xml(bare_xml).to_xml))
        .to eq("<r><lead>L</lead></r>")
      expect(klass.from_json(bare_json).to_json).to eq('{"lead":"L"}')
      expect(klass.from_yaml("lead: L\n").to_yaml).to eq("---\nlead: L\n")
      expect(klass.attributes[attr_name].cast_element(uninitialized, register))
        .to be(uninitialized)
    end
  end

  describe "the root cause" do
    # The module claims to protect self.cast for every subclass. It prepends
    # instance methods, so it never sees a class-level cast, which is why the
    # guard has to live in the attribute layer instead.
    it "is not covered by UninitializedClassGuard" do
      expect(Lutaml::Model::Type::Value.singleton_class.ancestors)
        .not_to include(Lutaml::Model::Type::UninitializedClassGuard)
      expect(PhantomValueSpec::Eager.cast(uninitialized))
        .to be_a(PhantomValueSpec::Eager)
    end

    it "leaves the sentinel alone at the one place a type is handed a value" do
      attr = PhantomValueSpec::RegularCollection.attributes[:things]

      expect(attr.cast_element(uninitialized, register)).to be(uninitialized)
      expect(attr.cast_value(uninitialized, register)).to be(uninitialized)
      expect(attr.default(register)).to be(uninitialized)
    end

    it "leaves nil alone there too" do
      attr = PhantomValueSpec::RegularCollection.attributes[:things]

      expect(attr.cast_element(nil, register)).to be_nil
      expect(attr.cast(nil, :json, register)).to be_nil
    end

    it "still casts real data" do
      attr = PhantomValueSpec::RegularCollection.attributes[:things]

      expect(attr.cast_element("x", register)).to be_a(PhantomValueSpec::Eager)
      expect(attr.cast_value(%w[x y], register).size).to eq(2)
    end
  end

  describe "S1c enum scalar, custom element type" do
    it "emits no element and no key for a source that carried neither" do
      emits_nothing_extra(PhantomValueSpec::EnumScalar, :role)
    end

    it "does not fail its own validator over a value nobody set" do
      expect { PhantomValueSpec::EnumScalar.new(lead: "L").validate! }
        .not_to raise_error
    end
  end

  describe "S1 enum scalar, built-in type (control)" do
    it "stays clean" do
      emits_nothing_extra(PhantomValueSpec::EnumScalarBuiltIn, :role)
    end
  end

  describe "S2c enum collection, custom element type" do
    it "emits no element and no key for a source that carried neither" do
      emits_nothing_extra(PhantomValueSpec::EnumCollection, :roles)
    end
  end

  describe "S2 enum collection, built-in type" do
    it "keeps an item pushed through the reader" do
      model = PhantomValueSpec::EnumCollectionBuiltIn.new(lead: "L",
                                                          roles: ["a"])
      model.roles << "b"

      expect(model.roles).to eq(%w[a b])
    end

    it "carries that item into the document" do
      model = PhantomValueSpec::EnumCollectionBuiltIn.new(lead: "L",
                                                          roles: ["a"])
      model.roles << "b"

      expect(compact(model.to_xml))
        .to eq("<r><lead>L</lead><roles>a</roles><roles>b</roles></r>")
    end

    it "keeps an item pushed onto a collection the document omitted" do
      model = PhantomValueSpec::EnumCollectionBuiltIn.from_xml(bare_xml)
      model.roles << "a"

      expect(model.roles).to eq(["a"])
      expect(compact(model.to_xml))
        .to eq("<r><lead>L</lead><roles>a</roles></r>")
    end

    it "still keeps duplicates out" do
      model = PhantomValueSpec::EnumCollectionBuiltIn.new(lead: "L")
      model.roles = ["a"]
      model.roles = %w[a b]

      expect(model.roles).to eq(%w[a b])
    end

    it "still keeps duplicates out through the shorthand writer" do
      model = PhantomValueSpec::EnumCollectionBuiltIn.new(lead: "L")
      model.a!
      model.a!
      model.b!

      expect(model.roles).to eq(%w[a b])
    end

    it "still removes a value through the shorthand writer" do
      model = PhantomValueSpec::EnumCollectionBuiltIn.new(lead: "L",
                                                          roles: %w[a b])
      model.a = false

      expect(model.roles).to eq(["b"])
    end
  end

  describe "S3 enum whose reader the model already defines" do
    it "leaves the model's own reader in charge" do
      expect(PhantomValueSpec::EnumPredefinedReader.new(lead: "L").role)
        .to eq("mine")
      expect(compact(PhantomValueSpec::EnumPredefinedReader.new(lead: "L").to_xml))
        .to eq("<r><lead>L</lead><role>mine</role></r>")
    end

    it "does not fabricate at the attribute layer behind it" do
      attr = PhantomValueSpec::EnumPredefinedReader.attributes[:role]

      expect(attr.cast_element(uninitialized, register)).to be(uninitialized)
    end
  end

  describe "S4 enum with non-String values (control)" do
    it "stays clean" do
      emits_nothing_extra(PhantomValueSpec::EnumNonString, :level)
    end

    it "generates no shorthand methods" do
      expect(PhantomValueSpec::EnumNonString.new(lead: "L")).not_to respond_to(:"1?")
    end
  end

  describe "S5 derived scalar" do
    # The reader calls into the cast on every call, with no writer in the
    # path, so a writer-side guard cannot reach this shape at all.
    it "emits no element and no key when the source method returns nothing" do
      emits_nothing_extra(PhantomValueSpec::DerivedScalar, :thing)
    end

    it "reads as nil rather than as a manufactured instance" do
      expect(PhantomValueSpec::DerivedScalar.new(lead: "L").thing).to be_nil
    end

    it "still casts what the source method does return" do
      model = PhantomValueSpec::DerivedScalarWithValue.new(lead: "L")

      expect(model.thing).to be_a(PhantomValueSpec::Eager)
      expect(compact(model.to_xml))
        .to eq(%(<r><lead>L</lead><thing>E("real")</thing></r>))
    end
  end

  describe "S6 derived collection" do
    it "emits no element and no key when the source method returns nothing" do
      emits_nothing_extra(PhantomValueSpec::DerivedCollection, :things)
    end

    it "reads as a collection, not as a bare instance" do
      expect(PhantomValueSpec::DerivedCollection.new(lead: "L").things).to eq([])
    end

    it "still casts every item the source method returns" do
      model = PhantomValueSpec::DerivedCollectionWithValues.new(lead: "L")

      expect(model.things.size).to eq(2)
      expect(model.things).to all(be_a(PhantomValueSpec::Eager))
      expect(compact(model.to_xml))
        .to eq(%(<r><lead>L</lead><things>E("x")</things><things>E("y")</things></r>))
    end

    it "reads an array source as many elements even with its own collection class" do
      model = PhantomValueSpec::DerivedCustomCollection.new(lead: "L")

      expect(model.things.size).to eq(2)
      expect(model.things.map(&:to_s)).to eq(['E("x")', 'E("y")'])
    end

    it "reads a single source value as a one-item collection, not a bare instance" do
      model = PhantomValueSpec::DerivedCollectionScalarSource.new(lead: "L")

      expect(model.things).to be_a(Array)
      expect(model.things.size).to eq(1)
      expect(model.things.first).to be_a(PhantomValueSpec::Eager)
      expect(compact(model.to_xml))
        .to eq(%(<r><lead>L</lead><things>E("x")</things></r>))
    end
  end

  describe "S7 derived where the name equals the method name" do
    it "falls through to the regular generator and stays clean" do
      attr = PhantomValueSpec::DerivedSameName.attributes[:thing]

      expect(attr.cast_element(uninitialized, register)).to be(uninitialized)
      expect(compact(PhantomValueSpec::DerivedSameName.new(lead: "L").to_xml))
        .to eq("<r><lead>L</lead></r>")
    end
  end

  describe "S8 derived whose reader the model already defines" do
    it "leaves the model's own reader in charge" do
      expect(compact(PhantomValueSpec::DerivedPredefinedReader.new(lead: "L").to_xml))
        .to eq("<r><lead>L</lead><thing>mine</thing></r>")
    end

    it "does not fabricate at the attribute layer behind it" do
      attr = PhantomValueSpec::DerivedPredefinedReader.attributes[:thing]

      expect(attr.cast_element(uninitialized, register)).to be(uninitialized)
    end
  end

  describe "S9 Reference scalar" do
    # cast_element returns before validate_attr_type!, so this shape
    # fabricated a live Reference even with a built-in type.
    it "does not build a Reference out of the sentinel" do
      attr = PhantomValueSpec::ReferenceScalar.attributes[:thing]

      expect(attr.cast_element(uninitialized, register)).to be(uninitialized)
      expect(attr.cast_value(uninitialized, register)).to be(uninitialized)
      expect(attr.default(register)).to be(uninitialized)
    end

    it "still builds one out of a real key" do
      attr = PhantomValueSpec::ReferenceScalar.attributes[:thing]

      expect(attr.cast_element("k1", register))
        .to be_a(Lutaml::Model::Type::Reference)
    end
  end

  describe "S10 Reference collection" do
    it "does not build a Reference out of the sentinel" do
      attr = PhantomValueSpec::ReferenceCollection.attributes[:things]

      expect(attr.cast_element(uninitialized, register)).to be(uninitialized)
      expect(attr.default(register)).to be(uninitialized)
    end
  end

  describe "the cast guard itself" do
    it "still reports an undeclared type when the value carries nothing" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :thing, :no_such_type_is_registered
      end

      expect { klass.new(thing: nil) }
        .to raise_error(Lutaml::Model::UnknownTypeError)
    end
  end

  describe "S11 regular scalar" do
    it "emits no element and no key for a source that carried neither" do
      emits_nothing_extra(PhantomValueSpec::RegularScalar, :thing)
    end

    it "reads as nil on a model built with no value for it" do
      expect(PhantomValueSpec::RegularScalar.new(lead: "L").thing).to be_nil
    end
  end

  describe "S12 regular collection, custom element type" do
    it "emits no element and no key for a source that carried neither" do
      emits_nothing_extra(PhantomValueSpec::RegularCollection, :things)
    end

    it "emits nothing on a plain mapping either" do
      expect(compact(PhantomValueSpec::RegularCollectionUnordered.from_xml(bare_xml).to_xml))
        .to eq("<r><lead>L</lead></r>")
    end

    it "leaves the collection empty rather than holding a made-up item" do
      expect(PhantomValueSpec::RegularCollection.from_xml(bare_xml).things)
        .to eq([])
    end

    it "still emits what the document did contain" do
      model = PhantomValueSpec::RegularCollection
        .from_xml("<r><lead>L</lead><things>P</things></r>")

      expect(compact(model.to_xml))
        .to eq(%(<r><lead>L</lead><things>E("P")</things></r>))
    end

    it "appends through the builder argument instead of replacing" do
      model = PhantomValueSpec::RegularCollection.new(lead: "L")
      model.things("x")
      model.things("y")

      expect(model.things.size).to eq(2)
    end
  end

  describe "S12b regular collection, built-in element type (control)" do
    it "was clean before and stays clean" do
      emits_nothing_extra(PhantomValueSpec::RegularCollectionBuiltIn, :things)
    end
  end

  describe "S13 regular attribute whose writer the model already defines" do
    # The value is cast before it reaches the model's own writer, so a
    # manufactured one gets laundered through code the library does not own.
    it "hands that writer nothing rather than a made-up value" do
      model = PhantomValueSpec::RegularPredefinedWriter.from_json(bare_json)

      expect(model.thing).to eq("seen(nil)")
    end

    it "does not fabricate at the attribute layer behind it" do
      attr = PhantomValueSpec::RegularPredefinedWriter.attributes[:thing]

      expect(attr.cast_element(uninitialized, register)).to be(uninitialized)
    end
  end

  describe "S14 regular attribute colliding with an enum value name" do
    it "emits no element for a source that carried none" do
      expect(compact(PhantomValueSpec::RegularEnumShorthandCollision.new(lead: "L").to_xml))
        .to eq("<r><lead>L</lead></r>")
      expect(compact(PhantomValueSpec::RegularEnumShorthandCollision.from_xml(bare_xml).to_xml))
        .to eq("<r><lead>L</lead></r>")
    end
  end

  describe "S17 regular collection with a custom Collection class" do
    it "emits no element for a source that carried none" do
      expect(compact(PhantomValueSpec::RegularCustomCollection.from_xml(bare_xml).to_xml))
        .to eq("<r><lead>L</lead></r>")
    end

    it "does not fail its own validator over a collection nobody filled" do
      expect { PhantomValueSpec::RegularCustomCollection.new(lead: "L").validate! }
        .not_to raise_error
    end
  end

  describe "S18 collection with a real default" do
    it "still emits the default" do
      expect(compact(PhantomValueSpec::SeededCollection.new(lead: "L").to_xml))
        .to eq(%(<r><lead>L</lead><things>E("seed")</things></r>))
      expect(compact(PhantomValueSpec::SeededCollection.from_xml(bare_xml).to_xml))
        .to eq(%(<r><lead>L</lead><things>E("seed")</things></r>))
    end
  end

  describe "S20 scalar with render_default on the mapping" do
    it "still emits the default" do
      expect(compact(PhantomValueSpec::RenderedDefault.new(lead: "L").to_xml))
        .to include("dflt")
      expect(compact(PhantomValueSpec::RenderedDefault.from_xml(bare_xml).to_xml))
        .to include("dflt")
    end
  end
end
