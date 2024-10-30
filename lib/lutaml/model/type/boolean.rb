module Lutaml
  module Model
    module Type
      class Boolean < Value
        def self.cast(value)
          return nil if value.nil?
          return true if value == true || value.to_s.match?(/^(true|t|yes|y|1)$/i)
          return false if value == false || value.to_s.match?(/^(false|f|no|n|0)$/i)
          value
        end

        def self.serialize(value)
          return nil if value.nil?
          value ? true : false
        end
      end

      register(:boolean, Lutaml::Model::Type::Boolean)
    end
  end
end
