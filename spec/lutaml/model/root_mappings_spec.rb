# module RootMapping
#   class RootUnits < Lutaml::Model::Serializable
#     attribute :enumerated_root_units, :string
#     attribute :unit, :string
#     attribute :power_denominator, :integer
#     attribute :power_numerator, :integer
#   end

#   class UnitPrefix < Lutaml::Model::Serializable
#     attribute :root_units, RootUnits

#     yaml do
#       root_mappings to: :root_units, path: %i[enumerated_root_units unit power_denominator power_numerator]
#     end
#   end
# end

# RSpec.describe RootMapping do
#   let(:mapper) { RootMapping::UnitPrefix }

#   let(:yaml) do
#     <<~YAML
#       "NISTu1":
#         root_units:
#           - enumerated_root_units:
#             unit: "meter"
#             power_denominator: 1
#             power_numerator: 1
#     YAML
#   end

#   context "with yaml" do
#     describe ".from_yaml" do
#       it "create model according to yaml" do
#         instance = mapper.from_yaml(yaml)
#         binding.irb
#         expect(instance.schemas.count).to eq(3)
#         expect(instance.schemas.map(&:id)).to eq(expected_ids)
#         expect(instance.schemas.map(&:path)).to eq(expected_paths)
#         expect(instance.schemas.map(&:name)).to eq(expected_names)
#       end
#     end

#     describe ".to_yaml" do
#       it "converts objects to yaml" do
#         schema1 = schema.new(id: "foo", path: "link one", name: "one")
#         schema2 = schema.new(id: "abc", path: "link two", name: "two")
#         schema3 = schema.new(id: "hello", path: "link three", name: "three")

#         instance = mapper.new(schemas: [schema1, schema2, schema3])

#         expect(instance.to_yaml).to eq(yaml)
#       end
#     end
#   end
# end
