# frozen_string_literal: true

# leptris#1941 consumer-gap law: the RAW-splice capability rides
# engine 1.9.406.0 (PLAN_OP_RAW + row identity). A bundle resolving
# an OLDER leptris gem — e.g. the metanorma consumer matrix pinned to
# 1.9.405.0 — must take the DOM lane, not the ops lane: splicing
# :raw without the engine constant emitted EMPTY fragments and the
# round-trip parse died on "empty input". The gate probes the FFI
# constant, so capability tracks the loaded gem, not a version
# table that drifts.
RSpec.describe Lutaml::Xml::Leptris::NativeEmission, '.raw_op_supported?' do
  it 'is false for an FFI surface without the RAW op' do
    plain = Class.new
    expect(described_class.raw_op_supported?(plain)).to be(false)
  end

  it 'is true when PLAN_OP_RAW is defined' do
    with_raw = Class.new { PLAN_OP_RAW = 4 }
    expect(described_class.raw_op_supported?(with_raw)).to be(true)
  end

  it 'probes the loaded gem by default (harness runs 1.9.406.0)' do
    expect(described_class.raw_op_supported?).to be(true)
  end
end
