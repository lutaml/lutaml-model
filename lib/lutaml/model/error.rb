module Lutaml
  module Model
    class Error < StandardError
    end
  end
end

require_relative "error/invalid_value_error"
require_relative "error/unknown_adapter_type_error"
