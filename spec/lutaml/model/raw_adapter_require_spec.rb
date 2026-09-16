# frozen_string_literal: true

# The adapter resolver loads adapter files by raw path (load_adapter_file),
# bypassing the autoload tree that normally defines Document before
# StandardAdapter references it at class-definition time. Each deep adapter
# require must therefore be self-sufficient.
RSpec.describe "raw adapter requires" do
  it "loads the json yeptris adapter without the namespace preloaded" do
    out = `bundle exec ruby -e 'require "lutaml/json/adapter/yeptris_adapter"; puts Lutaml::Json::Adapter::YeptrisAdapter.name' 2>&1`
    expect(out).to include("Lutaml::Json::Adapter::YeptrisAdapter")
  end

  it "loads the yaml yeptris adapter without the namespace preloaded" do
    out = `bundle exec ruby -e 'require "lutaml/yaml/adapter/yeptris_adapter"; puts Lutaml::Yaml::Adapter::YeptrisAdapter.name' 2>&1`
    expect(out).to include("Lutaml::Yaml::Adapter::YeptrisAdapter")
  end

  it "loads the json standard adapter standalone" do
    out = `bundle exec ruby -e 'require "lutaml/json/adapter/standard_adapter"; puts Lutaml::Json::Adapter::StandardAdapter.name' 2>&1`
    expect(out).to include("Lutaml::Json::Adapter::StandardAdapter")
  end
end
