# frozen_string_literal: true

require "spec_helper"

# The scalar-cast diversion (#978) must not capture element-form input:
# a type declaring its own .cast still receives parsed child elements
# through the mapping lane, which builds the model from its XML
# mapping. Diverting those into .cast raised IncorrectModelError
# downstream (uniword shared-schemas round-trips on 0.8.116/0.8.117).
RSpec.describe "cast routing for element-form input" do
  let(:styled_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :value, :string

      xml do
        element "style"
        map_attribute "value", to: :value
      end

      key_value do
        map "value", to: :value
      end

      def self.cast(value)
        return value if value.is_a?(self)

        new(value: value.to_s)
      end
    end
  end

  let(:host_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :style, "CastStyled"

      xml do
        element "host"
        map_element "style", to: :style
      end
    end
  end

  before do
    stub_const("CastStyled", styled_class)
    stub_const("CastHost", host_class)
  end

  it "builds element-form input through the mapping lane" do
    model = CastHost.from_xml('<host><style value="normal"/></host>')

    expect(model.style).to be_a(CastStyled)
    expect(model.style.value).to eq("normal")
  end
end
