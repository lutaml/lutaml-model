# rubocop:disable all
require "json"
require "lutaml/model"
require "lutaml/model/lml"
V = Lutaml::Model::Lml
DV = V::DocumentValidator
STR = {"kind"=>"builtin","name"=>"string"}
def attr(name = "x") = {"name"=>name,"type"=>STR}
def doc(attrs: [attr], mappings: nil)
  d = {"lml"=>2,"model"=>"A","register"=>"default","attributes"=>attrs}
  d["mappings"] = mappings if mappings
  d
end
def xml(m) = doc(mappings: {"xml"=>m})
def rule(r) = xml({"rules"=>[{"kind"=>"element","name"=>["a"],"to"=>"x"}.merge(r)]})
def nest(n, leaf = "x") = (1..n).inject(leaf) { |acc, _| [acc] }
def bundle(extra = {}) = {"lml_bundle"=>1,"roots"=>[],"models"=>{},"value_types"=>{},"capabilities"=>[]}.merge(extra)

cases = []
add = ->(name, kind, text) { cases << { "name"=>name, "kind"=>kind, "input"=>text } }
j = ->(h) { JSON.generate(h, max_nesting: false) }

add.("valid_control", "document", j.(doc))
["foo?","foo!","foo=","1a","Abc","a-b","a b","aé"].each { |n| add.("name_#{n}", "document", j.(doc(attrs: [attr(n)]))) }
%w[_x aB9 display hash schema_location send freeze].each { |n| add.("name_ok_#{n}", "document", j.(doc(attrs: [attr("ok"), attr(n)]))) }
DV::RESERVED_ATTRIBUTE_NAMES.each { |n| add.("reserved_#{n}", "document", j.(doc(attrs: [attr("ok"), attr(n)]))) }
add.("name_empty", "document", j.(doc(attrs: [attr("")])))
add.("name_ordered_content", "document", j.(doc(attrs: [attr("__lml_content")])))

add.("root_string", "document", j.(xml({"root"=>"a"})))
add.("root_array", "document", j.(xml({"root"=>[]})))
add.("root_null", "document", j.(xml({"root"=>nil})))
add.("root_ok", "document", j.(xml({"root"=>{"element"=>"a","mixed"=>true}})))
add.("root_element_empty", "document", j.(xml({"root"=>{"element"=>""}})))
add.("root_element_number", "document", j.(xml({"root"=>{"element"=>5}})))
add.("root_mixed_string", "document", j.(xml({"root"=>{"element"=>"a","mixed"=>"yes"}})))
add.("root_mixed_number", "document", j.(xml({"root"=>{"element"=>"a","mixed"=>1}})))
add.("json_root_mixed_string", "document", j.(doc(mappings: {"json"=>{"root"=>{"mixed"=>"no"}}})))
%w[child_mappings root_mappings].each do |k|
  add.("mapping_#{k}_array", "document", j.(xml({k=>[]})))
  add.("mapping_#{k}_string", "document", j.(xml({k=>"x"})))
  add.("mapping_#{k}_ok", "document", j.(xml({k=>{"a"=>"b"}})))
  add.("rule_#{k}_array", "document", j.(rule({k=>[]})))
  add.("rule_#{k}_null", "document", j.(rule({k=>nil})))
  add.("rule_#{k}_ok", "document", j.(rule({k=>{"a"=>"b"}})))
end
add.("rule_cdata_string", "document", j.(rule({"cdata"=>"true"})))
add.("rule_cdata_null", "document", j.(rule({"cdata"=>nil})))
add.("rule_cdata_ok", "document", j.(rule({"cdata"=>true})))
[["1a"],[""],["a b"],[5],["a:b"],[nil]].each do |(p)|
  ns = {"mode"=>"uri","uri"=>"urn:x","prefix"=>p}
  add.("prefix_#{p.inspect}_mapping", "document", j.(xml({"namespace"=>ns})))
  add.("prefix_#{p.inspect}_rule", "document", j.(rule({"namespace"=>ns})))
end
%w[a _a A1 a.b-c_d xml].each { |p| add.("prefix_ok_#{p}", "document", j.(xml({"namespace"=>{"mode"=>"uri","uri"=>"urn:x","prefix"=>p}}))) }

# typed defaults: a present default must match its builtin type.
INT = {"kind"=>"builtin","name"=>"integer"}
BOOL = {"kind"=>"builtin","name"=>"boolean"}
def dflt(type, value) = doc(attrs: [attr.merge("type"=>type, "default"=>{"present"=>true,"value"=>value})])
add.("default_int_on_string", "document", j.(dflt(STR, 5)))
add.("default_string_on_integer", "document", j.(dflt(INT, "5")))
add.("default_string_on_boolean", "document", j.(dflt(BOOL, "true")))
add.("default_array_on_string", "document", j.(dflt(STR, ["x"])))
add.("default_ok_integer", "document", j.(dflt(INT, 5)))
add.("default_ok_boolean", "document", j.(dflt(BOOL, false)))

# One accept and one refuse vector per builtin type. The accept values are
# what Lml.export_bundle writes (measured); the refuse values are the wrong
# JSON shape. qname is a plain string (never a {namespace, local} object) and
# every builtin but the integers (integer, positive_integer, non_negative_integer), boolean, float and hash is shape-checked only: the
# exporter passes a user's string through verbatim, so "abc" on a decimal is
# accepted (typed_default_ok_decimal_not_lexical).
TYPED_DEFAULTS = {
  "string"=>["s", 5], "token"=>["t", 5], "uri"=>["http://x/", 5], "email"=>["a@b.c", 5],
  "hostname"=>["h.example", 5], "ip"=>["1.2.3.4", 5], "boolean"=>[true, "true"], "integer"=>[5, "5"],
  "decimal"=>["1.5", true], "float"=>["1.5", 1.5], "rational"=>["1/2", true], "date"=>["2020-01-02", 20200102],
  "time"=>["2020-01-02T03:04:05Z", 3], "date_time"=>["2020-01-02T03:04:05+00:00", 3],
  "time_without_date"=>["03:04:05", 3], "duration"=>["P1D", 1],
  "qname"=>["a:b", {"namespace"=>"urn:x","local"=>"a"}], "base64_binary"=>["aGk=", 1],
  "hex_binary"=>["6869", 1], "symbol"=>["sym", 1], "hash"=>[{"a"=>1}, "x"],
  "email_address"=>["a@b.c", 5], "ip_v4_address"=>["1.2.3.4", 5], "ip_v6_address"=>["::1", 5],
  "uuid"=>["123e4567-e89b-12d3-a456-426614174000", 5], "reference"=>["r1", 5], "uri_reference"=>["a/b#c", 5],
  "date_with_timezone"=>["2020-01-02+05:00", 20200102], "date_time_with_timezone"=>["2020-01-02T03:04:05+05:00", 3],
  "day_time_duration"=>["P1D", 1], "year_month_duration"=>["P1Y", 1],
  "positive_integer"=>[5, "5"], "non_negative_integer"=>[0, "0"]
}
raise "update TYPED_DEFAULTS" unless TYPED_DEFAULTS.keys.sort == DV::BUILTIN_TYPES.sort
TYPED_DEFAULTS.each do |type, (ok, bad)|
  t = {"kind"=>"builtin","name"=>type}
  add.("typed_default_ok_#{type}", "document", j.(dflt(t, ok)))
  add.("typed_default_refused_#{type}", "document", j.(dflt(t, bad)))
end
add.("typed_default_ok_decimal_not_lexical", "document", j.(dflt({"kind"=>"builtin","name"=>"decimal"}, "abc")))

# What the exporter refuses (so no bundle carries these): an integer beyond
# +-(2**53 - 1), a float collection, a null float default, a JSON float
# inside a hash default. The validator refuses the same inputs.
add.("typed_default_ok_integer_max_safe", "document", j.(dflt(INT, 9007199254740991)))
add.("typed_default_ok_integer_min_safe", "document", j.(dflt(INT, -9007199254740991)))
add.("typed_default_refused_integer_2_53", "document", j.(dflt(INT, 9007199254740992)))
add.("typed_default_refused_integer_negative_2_53", "document", j.(dflt(INT, -9007199254740992)))
FLT = {"kind"=>"builtin","name"=>"float"}
coll = {"min"=>0,"max"=>nil}
add.("typed_default_refused_float_collection", "document",
     j.(doc(attrs: [attr.merge("type"=>FLT, "collection"=>coll, "default"=>{"present"=>true,"value"=>["1.5","2.5"]})])))
add.("typed_default_refused_float_empty_collection", "document",
     j.(doc(attrs: [attr.merge("type"=>FLT, "collection"=>coll, "default"=>{"present"=>true,"value"=>[]})])))
add.("typed_default_refused_float_null", "document", j.(dflt(FLT, nil)))
add.("typed_default_refused_hash_with_json_float", "document", j.(dflt({"kind"=>"builtin","name"=>"hash"}, {"a"=>1.5})))

# depth: root is level 1. Pad inside provenance (bundle) / default.value (document).
def deep_doc(levels)
  # levels: total container levels. root(1)+attributes(2)+attr(3)+default(4)=4, value nest adds the rest
  # The attribute is a hash so a nested default is well typed: {"v"=>...} is one level.
  extra = levels - 4
  hash_type = {"kind"=>"builtin","name"=>"hash"}
  doc(attrs: [attr.merge("type"=>hash_type, "default"=>{"present"=>true,"value"=>{"v"=>nest(extra - 1)}})])
end
[99, 100, 101].each { |n| add.("doc_depth_#{n}", "document", j.(deep_doc(n))) }
def deep_bundle(levels)
  bundle("provenance"=>{"p"=>nest(levels - 2)})
end
[99, 100, 101].each { |n| add.("bundle_depth_#{n}", "bundle", JSON.generate(deep_bundle(n), max_nesting: false)) }

# duplicate keys (text-level)
base = JSON.generate(bundle)
add.("dup_top", "bundle", base.sub(/\}\z/, ',"roots":[]}'))
add.("dup_escaped", "bundle", base.sub(/\}\z/, ',"roots":[]}'))
add.("dup_nested", "bundle", base.sub('"models":{}', '"models":{"A@d":{"lml":2},"A@d":{"lml":2}}'))
add.("dup_provenance", "bundle", base.sub(/\}\z/, ',"provenance":{"a":1,"a":2}}'))
add.("dup_in_array", "bundle", base.sub(/\}\z/, ',"provenance":{"l":[{"k":1,"k":2}]}}'))
add.("dup_none_same_key_different_objects", "bundle", base.sub(/\}\z/, ',"provenance":{"l":[{"k":1},{"k":2}],"m":{"k":3}}}'))
add.("dup_string_value_not_key", "bundle", base.sub(/\}\z/, ',"provenance":{"a":"b","c":"a"}}'))

out = cases.map do |c|
  exp =
    begin
      case c["kind"]
      when "document" then DV.validate!(JSON.parse(c["input"], max_nesting: false), kind: :document)
      else V::Importer.bundle(c["input"])
      end
      nil
    rescue V::RejectedError => e
      { "reason"=>e.reason.to_s, "location"=>e.location, "detail"=>e.detail }
    end
  c.merge("expect"=>exp)
end
File.binwrite(ARGV[0], JSON.pretty_generate(out) + "\n")
puts out.count { |c| c["expect"] }, out.size
out.each { |c| puts "#{c['name']}: #{c['expect']&.values_at('reason','location').inspect}" } if ENV["V"]
