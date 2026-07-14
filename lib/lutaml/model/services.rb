# frozen_string_literal: true

module Lutaml
  module Model
    module Services
      autoload :Base, "#{__dir__}/services/base"
      autoload :Type, "#{__dir__}/services/type"
    end
  end
end
