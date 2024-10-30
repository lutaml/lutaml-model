module Lutaml
  module Model
    module Type
      class Integer < Value
        def self.cast(value)
          return nil if value.nil?
          value.to_i
        end

        def self.serialize(value)
          return nil if value.nil?
          value.to_i
        end
      end

      register(:integer, Lutaml::Model::Type::Integer)
    end
  end
end
