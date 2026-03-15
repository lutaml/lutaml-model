# frozen_string_literal: true

# Check if XSD support is available (now integrated into lutaml-model)
begin
  require "lutaml/xml/schema/xsd"
  XSD_AVAILABLE = defined?(Lutaml::Xml::Schema::Xsd) ? true : false
rescue LoadError
  XSD_AVAILABLE = false
end

RSpec.configure do |config|
  config.before(:each, :xsd) do
    skip "XSD support not available" unless XSD_AVAILABLE
  end
end
