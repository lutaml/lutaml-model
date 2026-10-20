# frozen_string_literal: true

require "spec_helper"
require "open3"
require "lutaml/json/adapter/yeptris_adapter"

# Surface 1 of #978: the yeptris lane was selected from a bare
# constant check, so a process holding a half-initialized Yeptris
# module (the poison-process state the gem documents) committed to
# the native lane and failed pre-mapping on valid JSON — while other
# processes fell back to the standard lane, flipping the adapter
# choice across runs. Detection now probes the native engine; a
# broken native deterministically rides the standard lane.
RSpec.describe Lutaml::Model::AdapterResolver, ".adapter_for yeptris native detection" do
  let(:parse_probe) do
    <<~RUBY
      require "lutaml/model"

      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        key_value { map "v", to: :v }
      end

      model = klass.from_json('{"v": "scalar"}')
      adapter = Lutaml::Model::AdapterResolver.adapter_for(:json)
      puts "ADAPTER=\#{adapter.name.split('::').last} PARSED=\#{model.v}"
    RUBY
  end

  def subprocess_yeptris_capable?
    probe = <<~RUBY
      begin
        require "yeptris"
        exit(0)
      rescue LoadError
        exit(1)
      end
    RUBY
    _out, _err, status = Open3.capture3(RbConfig.ruby, "-I", "lib", "-e", probe)
    status.success?
  end

  it "resolves the yeptris lane when the native engine answers a probe" do
    skip "optional yeptris engine not resolvable outside the bundle" unless subprocess_yeptris_capable?

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", "lib", "-e", parse_probe)
    expect(status).to be_success, stderr
    expect(stdout).to include("ADAPTER=YeptrisAdapter")
    expect(stdout).to include("PARSED=scalar")
  end

  it "falls back to the standard lane when the native engine cannot parse" do
    poison = <<~RUBY
      require "lutaml/model"
      require "yeptris"
      require "lutaml/json/adapter/yeptris_adapter"

      # The poison state: the module is defined and require succeeds,
      # but every native parse fails. Whatever the cause (a stale
      # libyeptris, a half-initialized load), the lane must not be
      # selected.
      Lutaml::Json::Adapter::YeptrisAdapter
        .define_singleton_method(:native_ready?) { false }

      #{parse_probe}
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", "lib", "-e", poison)
    expect(status).to be_success, stderr
    expect(stdout).to include("ADAPTER=StandardAdapter")
    expect(stdout).to include("PARSED=scalar")
  end

  it "reports the adapter unavailable when the native probe fails" do
    allow(Lutaml::Json::Adapter::YeptrisAdapter)
      .to receive(:native_ready?).and_return(false)

    expect(Lutaml::Json::Adapter::YeptrisAdapter.available?).to be(false)
  ensure
    allow(Lutaml::Json::Adapter::YeptrisAdapter)
      .to receive(:native_ready?).and_call_original
  end
end
