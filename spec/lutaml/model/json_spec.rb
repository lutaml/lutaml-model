# frozen_string_literal: true

require "spec_helper"
require "lutaml/json"

RSpec.describe Lutaml::Model::Json do
  describe "standalone loading" do
    let(:lib_path) { File.expand_path("../../../lib", __dir__) }

    it "loads require 'lutaml/json' without preloading lutaml/model" do
      # rubocop:disable Style/CommandLiteral
      result = `#{RbConfig.ruby} -I#{lib_path} -e 'require "lutaml/json"; puts :ok' 2>&1`
      # rubocop:enable Style/CommandLiteral

      expect($?.success?).to be(true), result
      expect(result).to include("ok")
    end
  end

  describe "adapter autoloading" do
    it "does not autoload native JSON adapters on Opal" do
      %i[OjAdapter MultiJsonAdapter].each do |constant_name|
        hide_const("Lutaml::Json::Adapter::#{constant_name}")
      end

      allow(Lutaml::Model::RuntimeCompatibility).to receive(:opal?).and_return(true)
      load File.expand_path("../../../lib/lutaml/json/adapter.rb", __dir__)

      expect(Lutaml::Json::Adapter.autoload?(:OjAdapter)).to be_nil
      expect(Lutaml::Json::Adapter.autoload?(:MultiJsonAdapter)).to be_nil
    end
  end
end
