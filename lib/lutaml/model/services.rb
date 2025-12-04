# frozen_string_literal: true

module Lutaml
  module Model
    module Services
      autoload :Base, "#{__dir__}/services/base"
      autoload :DefaultValueResolver, "#{__dir__}/services/default_value_resolver"
      autoload :Type, "#{__dir__}/services/type"
    end
  end
end
