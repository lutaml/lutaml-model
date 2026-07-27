# frozen_string_string: true

require "spec_helper"

# When a caller assigns an unrelated Lutaml::Model::Serializable (not a
# declared subtype) to a typed slot, serialisation must use the value's own
# class mapping rules. The prior behaviour reused the declared
# attribute_type's child_transformation regardless of value.class, which
# silently applied the wrong rules and raised NoMethodError on whichever
# Ruby attribute name differed.
#
# See BUGREPORT.element-builder-dispatch-on-value-class.md for the original
# analysis and sts-ruby PR #47 for the downstream trigger.
RSpec.describe "ElementBuilder cross-class dispatch" do
  let(:declared_type) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      xml do
        root "declared"
        map_element "name", to: :name
      end
    end
  end

  let(:actual_type) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :different_name, :string

      xml do
        root "actual"
        map_element "different-name", to: :different_name
      end
    end
  end

  let(:holder_class) do
    declared = declared_type
    Class.new(Lutaml::Model::Serializable) do
      attribute :child, declared

      xml do
        root "holder"
        map_element "child", to: :child
      end
    end
  end

  it "serialises an unrelated Serializable using its own mapping" do
    holder = holder_class.new
    holder.child = actual_type.new(different_name: "x")
    xml = holder.to_xml

    parsed = Nokogiri::XML(xml)
    expect(parsed.at_css("different-name").content).to eq("x")
  end

  it "preserves the declared-type fast path for matching classes" do
    holder = holder_class.new
    holder.child = declared_type.new(name: "y")
    xml = holder.to_xml

    parsed = Nokogiri::XML(xml)
    expect(parsed.at_css("name").content).to eq("y")
  end

  it "round-trips the XML output (parsing yields declared type by design)" do
    # Deserialisation cannot infer the runtime-assigned class without a
    # discriminator; it instantiates the declared type. The XML round-trip
    # itself must still be lossless.
    holder = holder_class.new
    holder.child = actual_type.new(different_name: "round-trip")
    xml = holder.to_xml

    reparsed = holder_class.from_xml(xml)
    expect(reparsed.child).to be_a(declared_type)
    expect(xml).to include("<different-name>round-trip</different-name>")
  end
end
