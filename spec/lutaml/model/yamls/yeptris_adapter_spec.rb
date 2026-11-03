# frozen_string_literal: true

require "spec_helper"

# The yamls stream lane's yeptris adapter (#1078 family): when the
# native engine is available it is authoritative — an invalid document
# is skipped by resuming the stream after its reported error line and
# parsing the remainder with the engine; the standard (Psych) adapter
# never re-parses on this lane.
RSpec.describe "Yamls yeptris stream adapter" do
  before do
    skip "yeptris engine not available on this platform" unless
      Lutaml::Yamls::Adapter::YeptrisAdapter.available?
  end

  let(:invalid_last_stream) do
    <<~YAMLS
      ---
      full_name: John
      ---
      invalid yaml: [
    YAMLS
  end

  it "reports the engine as available where libyeptris loads" do
    expect(Lutaml::Model::Config.adapter_for(:yamls))
      .to be(Lutaml::Yamls::Adapter::YeptrisAdapter)
  end

  it "parses multi-document streams in order" do
    stream = "---\nfull_name: John\n---\nfull_name: Jane\n"
    docs = Lutaml::Yamls::Adapter::YeptrisAdapter.parse(stream)
    expect(docs.map { |d| d["full_name"] }).to eq(%w[John Jane])
  end

  it "warns and keeps the valid prefix when the last document is invalid" do
    expect do
      docs = Lutaml::Yamls::Adapter::YeptrisAdapter.parse(invalid_last_stream)
      expect(docs.map { |d| d["full_name"] }).to eq(["John"])
    end.to output(/Skipping invalid yaml: /).to_stderr
  end
end
