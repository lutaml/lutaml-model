# frozen_string_literal: true

require "teptris"

# TOML over the teptris engine (libteptris via FFI). teptris ships
# prebuilt platform gems for every platform we support — including
# mingw-ucrt — which retires the "no native TOML on Windows" gap that
# keeps tomlib off Windows. Value semantics mirror tomlib: offset and
# local datetimes become Time, dates become Date, local times stay
# String. Parse failures raise Teptris::ParseError (line/column).

module Lutaml
  module KeyValue
    module Adapter
      module Toml
        class TeptrisAdapter < Document
          def self.parse(toml, _options = {})
            Teptris::TOML.load(toml)
          end

          def to_toml(*)
            # Handle KeyValueElement input (new symmetric architecture)
            attributes_to_serialize = if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
                                        # Unwrap __root__ wrapper to get actual content
                                        @attributes.to_hash["__root__"]
                                      else
                                        # Legacy Hash input (backward compatibility)
                                        @attributes
                                      end

            Teptris::TOML.dump(attributes_to_serialize)
          end
        end
      end
    end
  end
end
