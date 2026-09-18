# frozen_string_literal: true

require "spec_helper"

# lutaml-model#687: an xs:sequence remembers a nested xs:choice
# compositor. Element rules inside `choice` take their position in the
# sequence and carry the choice on their model attributes, so validation
# applies order and exclusivity.
RSpec.describe "Sequence with nested choice" do
  let(:model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :title, :string
      attribute :hardcover, :string
      attribute :paperback, :string
      attribute :author, :string, collection: true

      xml do
        element "book"
        sequence do
          map_element "title", to: :title
          choice do
            map_element "hardcover", to: :hardcover
            map_element "papercover", to: :paperback
            map_element "paperback", to: :paperback
          end
          map_element "author", to: :author
        end
      end
    end
  end

  it "records the choice as a compositor alongside the flat order" do
    sequence = model.mappings_for(:xml).element_sequence.first
    expect(sequence.compositors).to contain_exactly(
      an_instance_of(Lutaml::Model::Choice),
    )
    choice = sequence.compositors.first
    # After finalize the choice carries the model attributes its rules
    # target — the shape validation machinery expects.
    expect(choice.attributes.map(&:name)).to eq(%i[hardcover paperback])
  end

  it "keeps the model attributes tagged with the nested choice" do
    choice = model.mappings_for(:xml).element_sequence.first.compositors.first
    expect(model.attributes[:hardcover].options[:choice]).to equal(choice)
    expect(model.attributes[:paperback].options[:choice]).to equal(choice)
  end

  it "validates order and exclusivity" do
    valid = model.from_xml(
      "<book><title>T</title><paperback>PB</paperback><author>A</author></book>",
    )
    expect(valid.validate).to be_empty

    out_of_order = model.from_xml(
      "<book><author>A</author><title>T</title><hardcover>HB</hardcover></book>",
    )
    expect(out_of_order.validate).not_to be_empty

    both_branches = model.from_xml(
      "<book><title>T</title><hardcover>HB</hardcover>" \
      "<paperback>PB</paperback><author>A</author></book>",
    )
    expect(both_branches.validate).not_to be_empty
  end
end
