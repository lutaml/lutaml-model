# frozen_string_literal: true

# leptris#1966 root cause: the emission graph numbered :nested rows
# only, but emission_rows_for materializes :ordered_deferred rows
# WITH child :plan trees (the deferred subtree is fully materialized
# — the recursive gate guarantees it). A valued deferred row under
# an ordered parent (uniword's theme/styles shapes) then looked up
# graph[tree] at emit time, got nil, and the element op carried
# plan_index=nil — the engine rejected the stream with -5. The
# graph must number every row kind that carries a plan.
RSpec.describe Lutaml::Xml::Leptris::NativeEmission,
               ".emission_graph_for numbers deferred subtrees" do
  let(:child_tree) do
    { name: "p", children: [{ name: "t", kind: :scalar }] }
  end
  let(:tree) do
    { name: "root", children: [
      { name: "body", kind: :ordered_deferred, plan: child_tree },
    ] }
  end
  let(:plan) do
    { ordered: true, tree: tree, emission_tree: tree, rows: [] }
  end

  it "assigns the deferred subtree a graph slot" do
    graph = described_class.emission_graph_for(plan, :register)
    expect(graph[tree]).to eq(0)
    expect(graph[child_tree]).to eq(1)
  end
end
