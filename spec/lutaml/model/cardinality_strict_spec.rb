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

  # Singular attribute deserialized by a custom method. The custom method must
  # not mask an over-count: multiple children into a singular attribute stay a
  # cardinality violation, exactly as for the plain (non-custom) mapping above.
  class CustomSingular < Lutaml::Model::Serializable
    attribute :label, :string

    xml do
      root "custom_singular"
      map_element "label", to: :label,
                           with: { from: :label_from, to: :label_to }
    end

    def label_from(model, node)
      model.label = node.text.upcase
    end

    def label_to(model, parent, doc); end
  end
end

# #185 asks for cardinality enforcement across XML AND key/value formats.
# Key/value formats already raise at parse (an over-count arrives as an array);
# this change brings XML in line. These examples prove the behaviour for every
# format.
RSpec.describe "Issue #185 strict cardinality" do
  describe "non-collection attribute (default 0..1) given more than one value" do
    it "raises at parse for XML (multiple elements)" do
      expect do
        CardinalityStrictSpec::Simple.from_xml(
          "<simple><name>A</name><name>B</name></simple>",
        )
      end.to raise_error(Lutaml::Model::CollectionTrueMissingError, /`name`/)
    end

    {
      json: ['{"name":["A","B"]}', '{"name":"A"}'],
      yaml: ["name:\n- A\n- B\n", "name: A\n"],
      toml: ['name = ["A", "B"]', 'name = "A"'],
    }.each do |format, (over_count, single)|
      it "raises at parse for #{format.upcase} (array on a singular attribute)" do
        expect do
          CardinalityStrictSpec::Simple.public_send(:"from_#{format}",
                                                    over_count)
        end.to raise_error(Lutaml::Model::CollectionTrueMissingError, /`name`/)
      end

      it "accepts a single #{format.upcase} value" do
        obj = CardinalityStrictSpec::Simple.public_send(:"from_#{format}",
                                                        single)
        expect(obj.name).to eq("A")
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
      it "still raises at parse for multiple XML elements" do
        expect do
          CardinalityStrictSpec::CustomSingular.from_xml(
            "<custom_singular><label>a</label><label>b</label>" \
            "</custom_singular>",
          )
        end.to raise_error(Lutaml::Model::CollectionTrueMissingError, /`label`/)
      end

      it "runs the custom method for a single XML element" do
        obj = CardinalityStrictSpec::CustomSingular.from_xml(
          "<custom_singular><label>hi</label></custom_singular>",
        )
        expect(obj.label).to eq("HI")
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
end
