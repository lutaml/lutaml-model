# lib/lutaml/model/serializable.rb
require_relative "serialize"

module Lutaml
  module Model
    class Serializable
      include Serialize
    end
  end
end
