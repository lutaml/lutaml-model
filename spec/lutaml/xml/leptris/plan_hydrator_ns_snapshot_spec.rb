require "spec_helper"
require_relative "../../../../lib/lutaml/model"

# leptris#1874: the plan hydrator's namespace collection collapses the
# whole-subtree Ruby recursion (one namespace_definitions FFI crossing
# per node) into the engine's bulk snapshot face when the binding
# exposes it. These specs pin the ROW CONTRACT the binding must
# satisfy and the dispatch, so the binding PR can be verified without
# waiting for the native pin bump.
# A real lightweight struct standing in for the future binding
# element: responds to the bulk face with fixed rows, carries no
# behavior of its own.
SnapshotFaceElement = Struct.new(:rows) do
  def namespace_declarations_snapshot
    rows
  end
end

RSpec.describe Lutaml::Xml::Leptris::PlanHydrator do
  describe ".ns_data_from_snapshot_rows" do
    it "builds the ns_data hash from pre-order snapshot rows" do
      rows = [
        { path: [], prefix: nil, href: "urn:d" },
        { path: [], prefix: "a", href: "urn:a" },
        { path: ["c1"], prefix: "b", href: "urn:b" },
        { path: ["c2"], prefix: nil, href: "urn:d2" },
      ]

      result = described_class.ns_data_from_snapshot_rows(rows)

      expect(result).to eq(
        [] => { default: { uri: "urn:d", prefix: nil,
                           format: :default },
                "a" => { uri: "urn:a", prefix: "a", format: :prefix } },
        ["c1"] => { "b" => { uri: "urn:b", prefix: "b",
                             format: :prefix } },
        ["c2"] => { default: { uri: "urn:d2", prefix: nil,
                               format: :default } },
      )
    end

    it "returns an empty hash for a declaration-free subtree" do
      expect(described_class.ns_data_from_snapshot_rows([])).to eq({})
    end
  end

  describe "the snapshot face probe in collect_native_namespaces" do
    it "prefers the bulk face when the binding exposes it" do
      element = SnapshotFaceElement.new(
        [{ path: ["x"], prefix: "p", href: "urn:p" }],
      )

      result = described_class.collect_native_namespaces(element)

      expect(result).to eq(
        ["x"] => { "p" => { uri: "urn:p", prefix: "p",
                            format: :prefix } },
      )
    end
  end
end
