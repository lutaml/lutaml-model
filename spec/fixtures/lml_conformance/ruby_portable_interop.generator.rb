# rubocop:disable all
# Generates ruby_portable_interop.json: an Lml bundle of Interop::Rec/Tag plus
# the Lml.portable_json text of three records (hash floats, -0.0, 0.0, big
# integers, nested model, collections). Ruby owns this corpus; the TS and Rust
# generated JSON codecs must read each output and write it back identically.
#   ruby -Ilib spec/fixtures/lml_conformance/ruby_portable_interop.generator.rb OUT.json
require "lutaml/model"
require "lutaml/model/lml"
require "bigdecimal"
require "json"
module Interop
  class Tag < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :weight, :float
    json { map "name", to: :name; map "weight", to: :weight }
  end
  class Rec < Lutaml::Model::Serializable
    attribute :label, :string
    attribute :count, :integer
    attribute :counts, :integer, collection: true
    attribute :price, :decimal
    attribute :ratio, :float
    attribute :open, :boolean
    attribute :meta, :hash
    attribute :tag, Tag
    attribute :tags, Tag, collection: true
    json do
      map "label", to: :label; map "count", to: :count; map "counts", to: :counts
      map "price", to: :price; map "ratio", to: :ratio; map "open", to: :open
      map "meta", to: :meta; map "tag", to: :tag; map "tags", to: :tags
    end
  end
end
recs = [
 Interop::Rec.new(label: "big", count: 9_007_199_254_740_993, counts: [-7, 0, 2**70], price: BigDecimal("0.15e1"), ratio: 1e20, open: false, meta: {"k"=>[1,nil], "f"=>0.1, "e"=>1e21, "s"=>1.5e-7, "one"=>1.0, "n"=>-2.5e-5, "m"=>123.456, "max"=>Float::MAX, "min"=>5.0e-324, "zero"=>0.0, "o"=>{"d"=>true, "x"=>"y"}}, tag: Interop::Tag.new(name: "t", weight: -0.0), tags: [Interop::Tag.new(weight: 1e-5), Interop::Tag.new(weight: 123456.789)]),
 Interop::Rec.new(count: -1, price: BigDecimal("-0.0"), ratio: 5.0e-324),
 Interop::Rec.new(price: BigDecimal("1e-7"), ratio: Float::MAX),
]
bundle = Lutaml::Model::Lml.export_bundle([Interop::Rec])
File.binwrite(ARGV.fetch(0), JSON.generate("bundle" => bundle.to_h, "outputs" => recs.map { |r| Lutaml::Model::Lml.portable_json(r) }))
