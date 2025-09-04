require "spec_helper"

# Simple model with basic attributes
class ComparableGlaze < Lutaml::Model::Serializable
  attribute :color, :string
  attribute :temperature, :integer
  attribute :food_safe, :boolean
end

# Model with a nested Serializable object
class ComparableCeramic < Lutaml::Model::Serializable
  attribute :type, :string
  attribute :glaze, ComparableGlaze
end

# Model with a deeply nested Serializable object
class ComparableCeramicCollection < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :featured_piece, ComparableCeramic # This creates a two-level nesting
end

class RecursiveNode < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :next_node, RecursiveNode
end

# Model with collection attributes for diff testing
class ComparablePerson < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :children, ComparablePerson, collection: true
end

RSpec.describe Lutaml::Model::ComparableModel do
  describe "comparisons" do
    context "with simple types (Glaze)" do
      it "compares equal objects with basic attributes" do
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        expect(glaze1).to eq(glaze2)
        expect(glaze1.hash).to eq(glaze2.hash)
      end

      it "compares unequal objects with basic attributes" do
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Red", temperature: 1000,
                                     food_safe: false)
        expect(glaze1).not_to eq(glaze2)
        expect(glaze1.hash).not_to eq(glaze2.hash)
      end
    end

    context "with nested Serializable objects (Ceramic)" do
      it "compares equal objects with one level of nesting" do
        # Here, we're comparing Ceramic objects that contain Glaze objects
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        ceramic1 = ComparableCeramic.new(type: "Bowl", glaze: glaze1)
        ceramic2 = ComparableCeramic.new(type: "Bowl", glaze: glaze2)
        expect(ceramic1).to eq(ceramic2)
        expect(ceramic1.hash).to eq(ceramic2.hash)
      end

      it "compares unequal objects with one level of nesting" do
        # Here, we're comparing Ceramic objects with different Glaze objects
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Red", temperature: 1000,
                                     food_safe: false)
        ceramic1 = ComparableCeramic.new(type: "Bowl", glaze: glaze1)
        ceramic2 = ComparableCeramic.new(type: "Plate", glaze: glaze2)
        expect(ceramic1).not_to eq(ceramic2)
        expect(ceramic1.hash).not_to eq(ceramic2.hash)
      end
    end

    context "with deeply nested Serializable objects (CeramicCollection)" do
      let(:first_collection) do
        ComparableCeramicCollection.new(
          name: "Blue Collection",
          featured_piece: ComparableCeramic.new(
            type: "Bowl",
            glaze: ComparableGlaze.new(
              color: "Blue",
              temperature: 1200,
              food_safe: true,
            ),
          ),
        )
      end

      let(:second_collection) do
        ComparableCeramicCollection.new(
          name: "Blue Collection",
          featured_piece: ComparableCeramic.new(
            type: "Bowl",
            glaze: ComparableGlaze.new(
              color: "Blue",
              temperature: 1200,
              food_safe: true,
            ),
          ),
        )
      end

      it "compares equal objects with two levels of nesting" do
        # This test compares CeramicCollection objects that contain Ceramic objects,
        # which in turn contain Glaze objects - a two-level deep nesting
        expect(first_collection).to eq(second_collection)
      end

      it "generates same hash for objects with two levels of nesting" do
        expect(first_collection.hash).to eq(second_collection.hash)
      end

      context "with deeply nested objects that are not equal" do
        before do
          second_collection.name = "Red Collection"
          second_collection.featured_piece.type = "Plate"
          second_collection.featured_piece.glaze.color = "Red"
        end

        it "compares unequal objects with two levels of nesting" do
          # This test compares CeramicCollection objects that are different at every level:
          # the collection name, the ceramic type, and the glaze properties
          expect(first_collection).not_to eq(second_collection)
        end

        it "generates different hashes for objects with two levels of nesting" do
          expect(first_collection.hash).not_to eq(second_collection.hash)
        end
      end
    end

    context "with recursive relationships" do
      let(:first_recursive_node) do
        node1 = RecursiveNode.new(name: "A")
        node2 = RecursiveNode.new(name: "B", next_node: node1)
        node1.next_node = node2
        node1
      end

      let(:second_recursive_node) do
        node1 = RecursiveNode.new(name: "A")
        node2 = RecursiveNode.new(name: "B", next_node: node1)
        node1.next_node = node2
        node1
      end

      describe ".eql?" do
        it "compares equal objects" do
          expect(first_recursive_node).to eq(second_recursive_node)
        end

        it "compares unequal objects" do
          second_recursive_node.name = "X"
          expect(first_recursive_node).not_to eq(second_recursive_node)
        end
      end

      describe ".hash" do
        it "returns the same hash for equal objects" do
          expect(first_recursive_node.hash).to eq(second_recursive_node.hash)
        end

        it "returns different hashes for unequal objects" do
          second_recursive_node.name = "X"
          expect(first_recursive_node.hash).not_to eq(second_recursive_node.hash)
        end
      end
    end

    context "with diff_with_score and collection attributes" do
      let(:person_one_yaml) do
        <<~YAML
          ---
          name: Alice
          children:
            - name: Alice
              children:
              - name: Alice1
              - name: Bob1
            - name: Bob
              children:
              - name: Alice2
              - name: Bob2
        YAML
      end

      let(:person_one) do
        ComparablePerson.from_yaml(person_one_yaml)
      end

      let(:person_two_yaml) do
        <<~YAML
          ---
          name: Bob
          children:
            - name: Alice1
              children:
              - name: Alice1
              - name: Bob2
            - name: Bob2
              children:
              - name: Alice1
              - name: Bob2
        YAML
      end

      let(:person_two) do
        ComparablePerson.from_yaml(person_two_yaml)
      end

      it "generates diff tree with collection attribute names" do
        diff_score, diff_tree = Lutaml::Model::Serialize.diff_with_score(person_one, person_two)

        expect(diff_score).to be_a(Float)
        expect(diff_tree).to be_a(String)

        expect(diff_tree).to include("children (collection)")

        expect(diff_tree).to include("name (Lutaml::Model::Type::String)")
        expect(diff_tree).to include('- (String) "Alice"')
        expect(diff_tree).to include('+ (String) "Bob"')
      end

      it "shows the complete nested structure in diff tree" do
        _diff_score, diff_tree = Lutaml::Model::Serialize.diff_with_score(person_one, person_two)

        expect(diff_tree).to include("└── ComparablePerson")
        expect(diff_tree).to include("├── name (Lutaml::Model::Type::String)")
        expect(diff_tree).to include("└── children (collection)")

        expect(diff_tree).to match(/children \(collection\).*\[1\].*ComparablePerson.*children \(collection\)/m)
      end
    end
  end
end
