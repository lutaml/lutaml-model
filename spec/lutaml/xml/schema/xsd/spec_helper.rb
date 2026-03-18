# frozen_string_literal: true

require "lutaml/xml/schema/xsd"

module XsdSpecHelper
  FIXTURES_DIR = File.expand_path("../../../../fixtures/xml/schema/xsd",
                                  __dir__)

  def xsd_fixture_path(filename)
    File.join(FIXTURES_DIR, filename)
  end

  def load_xsd_fixture(filename)
    File.read(xsd_fixture_path(filename))
  end

  def skip_if_missing_gem(gem_name)
    yield
  rescue LoadError
    skip "#{gem_name} not available"
  end
end

RSpec.configure do |config|
  config.include XsdSpecHelper
end
