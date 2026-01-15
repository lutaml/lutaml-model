require "bundler/setup"
require "lutaml/model"

class BooleanPresenceModel < Lutaml::Model::Serializable
  attribute :active, Lutaml::Model::Type::Boolean
  attribute :enabled, Lutaml::Model::Type::Boolean

  xml do
    root "BooleanPresenceModel"
    map_element "Active", to: :active, value_map: {
      from: { empty: true, omitted: false },
      to: { true: :empty, false: :omitted }
    }
    map_element "Enabled", to: :enabled, value_map: {
      from: { empty: true, omitted: false },
      to: { true: :empty, false: :omitted }
    }
  end
end

# Test serialization
puts "=== Test 1: Serialize with active=true, enabled=false ==="
model1 = BooleanPresenceModel.new(active: true, enabled: false)
xml1 = model1.to_xml
puts xml1
puts
# Expected: <BooleanPresenceModel><Active/></BooleanPresenceModel>

# Test serialization with both true
puts "=== Test 2: Serialize with active=true, enabled=true ==="
model2 = BooleanPresenceModel.new(active: true, enabled: true)
xml2 = model2.to_xml
puts xml2
puts
# Expected: <BooleanPresenceModel><Active/><Enabled/></BooleanPresenceModel>

# Test serialization with both false
puts "=== Test 3: Serialize with active=false, enabled=false ==="
model3 = BooleanPresenceModel.new(active: false, enabled: false)
xml3 = model3.to_xml
puts xml3
puts
# Expected: <BooleanPresenceModel/>

# Test deserialization with empty element
puts "=== Test 4: Deserialize with empty element (should be true) ==="
xml_input = "<BooleanPresenceModel><Active/></BooleanPresenceModel>"
model4 = BooleanPresenceModel.from_xml(xml_input)
puts "active: #{model4.active.inspect}, enabled: #{model4.enabled.inspect}"
puts
# Expected: active: true, enabled: nil (or some default)

# Test deserialization with absent element
puts "=== Test 5: Deserialize with absent element ==="
xml_input2 = "<BooleanPresenceModel/>"
model5 = BooleanPresenceModel.from_xml(xml_input2)
puts "active: #{model5.active.inspect}, enabled: #{model5.active.inspect}"
puts
# Expected: active: nil (or Uninitialized)
