# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml"
require "lutaml/xml/schema/xsd"

# The XSD schema-object classes carry hand-written XML mappings; a `to:`
# that does not name a declared attribute compiles fine and then crashes
# at parse time with "Attribute '...' not found" — for ANY document that
# contains the class, because the rule loop validates every mapping rule
# against the instance, not only the children present (#1025: redefine
# shipped to: :simpleType / :complexType / :attributeGroup against
# simple_type / complex_type / attribute_group). This sweep pins every
# registered model's element and attribute rules to declared attributes
# so the whole typo family fails here, at spec time.
RSpec.describe "XSD schema model mapping integrity" do
  it "maps every element rule of every registered model to a declared attribute" do
    broken = []

    Lutaml::Xml::Schema::Xsd.register.models.each_value do |klass|
      next unless klass.is_a?(Class) && klass.include?(Lutaml::Model::Serialize)

      mapping = klass.mappings_for(:xml)
      mapping.mapping_elements_hash.each_value do |rule_or_array|
        Array(rule_or_array).each do |rule|
          unless klass.attributes.key?(rule.to)
            broken << "#{klass.name}: map_element #{rule.name.inspect} -> " \
                      "#{rule.to.inspect}"
          end
        end
      end
    end

    expect(broken).to be_empty, <<~MSG
      mapping rules point at undeclared attributes:
      #{broken.join("\n")}
    MSG
  end

  it "maps every attribute rule of every registered model to a declared attribute" do
    broken = []

    Lutaml::Xml::Schema::Xsd.register.models.each_value do |klass|
      next unless klass.is_a?(Class) && klass.include?(Lutaml::Model::Serialize)

      mapping = klass.mappings_for(:xml)
      mapping.mapping_attributes_hash.each_value do |rule_or_array|
        Array(rule_or_array).each do |rule|
          unless klass.attributes.key?(rule.to)
            broken << "#{klass.name}: map_attribute #{rule.name.inspect} -> " \
                      "#{rule.to.inspect}"
          end
        end
      end
    end

    expect(broken).to be_empty, <<~MSG
      mapping rules point at undeclared attributes:
      #{broken.join("\n")}
    MSG
  end

  # #1025: the regression that motivated the sweep — a redefine with a
  # group child parses, and each redefined member kind lands on its
  # declared attribute.
  it "parses xs:redefine with group, simpleType, complexType and attributeGroup" do
    doc = Lutaml::Xml::Schema::Xsd.parse(<<~XSD)
      <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <xsd:redefine schemaLocation="base.xsd">
          <xsd:group name="g">
            <xsd:choice><xsd:element name="e1"/></xsd:choice>
          </xsd:group>
          <xsd:simpleType name="st">
            <xsd:restriction base="xsd:string"/>
          </xsd:simpleType>
          <xsd:complexType name="ct">
            <xsd:sequence><xsd:element name="x"/></xsd:sequence>
          </xsd:complexType>
          <xsd:attributeGroup name="ag"/>
        </xsd:redefine>
      </xsd:schema>
    XSD

    redefined = doc.redefine.first

    expect(redefined.group.name).to eq("g")
    expect(redefined.simple_type.name).to eq("st")
    expect(redefined.complex_type.name).to eq("ct")
    expect(redefined.attribute_group.name).to eq("ag")
    expect(redefined.schema_path).to eq("base.xsd")
  end
end
