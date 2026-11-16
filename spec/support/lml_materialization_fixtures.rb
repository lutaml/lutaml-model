# frozen_string_literal: true

# Hand-authored contract (01) bundles for Materialization specs. String
# keys, as DocumentValidator emits them. No Ruby model constants exist
# for these ids: materialization must work from the data alone.
module LmlMaterializationFixtures
  module_function

  def string_type
    { "kind" => "builtin", "name" => "string" }
  end

  def model_type(id)
    { "kind" => "model", "id" => id }
  end

  def model(name, attributes, register: "default")
    { "lml" => 2, "model" => name, "register" => register, "attributes" => attributes }
  end

  def bundle(models)
    { "lml_bundle" => 1, "roots" => models.keys.sort, "models" => models,
      "value_types" => {}, "capabilities" => [] }
  end

  # Order -> Line (collection) -> Order (cycle), Order has a self-tree.
  def cyclic
    order = "Shop::Order@default"
    line = "Shop::Line@default"
    bundle(
      order => model("Shop::Order", [
                       { "name" => "id", "type" => string_type, "required" => true },
                       { "name" => "status", "type" => string_type, "values" => %w[open closed],
                         "default" => { "present" => true, "value" => "open" } },
                       { "name" => "lines", "type" => model_type(line),
                         "collection" => { "min" => 0, "max" => nil } },
                       { "name" => "parent", "type" => model_type(order) },
                     ]),
      line => model("Shop::Line", [
                      { "name" => "sku", "type" => string_type },
                      { "name" => "order", "type" => model_type(order) },
                      { "name" => "qty", "type" => string_type,
                        "collection" => { "min" => 1, "max" => 3 } },
                    ]),
    )
  end

  def with_value_type
    bundle("Shop::Item@default" => model("Shop::Item", [
                                           { "name" => "code", "type" => { "kind" => "value", "id" => "Shop::Sku" } },
                                         ]))
  end
end
