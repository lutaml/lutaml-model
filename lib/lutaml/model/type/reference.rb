module Lutaml
  module Model
    module Type
      class Reference < Value
        attr_reader :key

        def initialize(model_class, key_attribute, key = nil)
          @model_class = model_class.to_s
          @key_attribute = key_attribute
          @key = key
          super(object)
        end

        def object
          return @value if resolved?
          return nil unless @key

          @value = Lutaml::Model::Store.resolve(@model_class, @key_attribute,
                                                @key)
          @value
        end

        def pretty_print_instance_variables
          (instance_variables - %i[@value @key_attribute @model_class]).sort
        end

        def resolved?
          model_instance?(@value)
        end

        # Enhanced casting method that receives metadata
        def self.cast_with_metadata(value, model_class, key_attribute)
          return value if value.is_a?(Reference)

          new(model_class, key_attribute, value)
        end

        def self.serialize(value)
          case value
          when Reference
            value.key
          else
            value.to_s
          end
        end

        def to_xml
          key&.to_s
        end

        def to_json(*_args)
          key
        end

        def to_yaml
          key
        end

        def to_hash
          key
        end

        def to_toml
          key&.to_s
        end

        def self.from_xml(value)
          cast(value)
        end

        def self.from_json(value)
          cast(value)
        end

        def self.from_yaml(value)
          cast(value)
        end

        def self.from_hash(value)
          cast(value)
        end

        def self.from_toml(value)
          cast(value)
        end

        private

        def model_instance?(value)
          return false unless value

          klass = Object.const_get(@model_class)
          value.instance_of?(klass)
        rescue NameError
          false
        end
      end
    end
  end
end
