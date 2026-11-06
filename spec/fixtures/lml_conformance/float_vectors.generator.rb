# rubocop:disable all
# Generates float_vectors.json: IEEE-754 doubles with the LML `float` wire
# string Ruby's Lutaml::Model::Lml::DocumentValidator.float_wire produces.
# Ruby owns this corpus; the TS and Rust ports must reproduce every wire.
#   ruby -Ilib spec/fixtures/lml_conformance/float_vectors.generator.rb OUT.json
require "json"
require "lutaml/model"
require "lutaml/model/lml"

DV = Lutaml::Model::Lml::DocumentValidator

def from_bits(bits) = [bits].pack("Q>").unpack1("G")
def bits_of(float) = [float].pack("G").unpack1("Q>")

values = []
add = ->(f) { values << f if f.finite? }

# fixed landmarks
[0.0, -0.0, 1.0, -1.0, 0.5, 0.1, 0.2, 0.3, 1.5, 100.0, 123456.789,
 1e14, 1e15, 1e16, 1e17, 1e21, 1e22, 1e100, 1e300, 1e-4, 1e-5, 1e-6, 1e-10, 1e-100,
 9.999999999999998e14, 9.999999999999999e14, 1234567890123456.0, 1151450203773890.8,
 123456789012345.6, 9007199254740991.0, 9007199254740992.0, 0.00011, 0.000099999,
 Float::MAX, -Float::MAX, Float::MIN, -Float::MIN, Float::EPSILON,
 5.0e-324, -5.0e-324, 2.2250738585072009e-308, 2.225073858507201e-308].each(&add)

# every notation boundary and its immediate neighbours (bit steps)
[1e-5, 1e-4, 1e15, 1e16, 1e-323, Float::MIN, Float::MAX, 1.0, 10.0, 1e22].each do |b|
  (-20..20).each { |d| add.(from_bits(bits_of(b) + d)); add.(-from_bits(bits_of(b) + d)) }
end

# smallest/largest subnormals and the subnormal/normal seam
(1..32).each { |n| add.(from_bits(n)); add.(-from_bits(n)) }
(-16..16).each { |d| add.(from_bits(0x0010000000000000 + d)) }

# every power of ten and of two
(-323..308).each { |e| add.(Float("1e#{e}")) }
(-1074..1023).each { |e| add.(2.0**e) }

rng = Random.new(1033)
# [1e15, 1e16): 16 and 17 significant digits (integers, .5 and arbitrary fractions)
300.times { add.(1e15 + rng.rand * 9e15) }
200.times { add.((1e15 + rng.rand(9e15)).floor.to_f) }
200.times { add.((1e15 + rng.rand(9e15)).floor + 0.5) }
200.times { add.((1e15 + rng.rand(9e14)).floor + rng.rand(10) / 10.0) }
# around the small boundary
200.times { add.(1e-5 * (0.5 + rng.rand * 20)) }
200.times { add.(1e-4 * (0.5 + rng.rand * 20)) }
# uniformly random bit patterns (all magnitudes, both signs)
600.times { add.(from_bits(rng.rand(2**64))) }

seen = {}
out = values.filter_map do |f|
  bits = format("%016x", bits_of(f))
  next if seen[bits]

  seen[bits] = true
  { "bits" => bits, "wire" => DV.float_wire(f) }
end
File.write(ARGV.fetch(0), JSON.pretty_generate(out) + "\n")
puts out.size
