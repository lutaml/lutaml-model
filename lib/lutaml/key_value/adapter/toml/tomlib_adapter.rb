require "tomlib"

module Lutaml
  module KeyValue
    module Adapter
      module Toml
        class TomlibAdapter < Document
          # Issue warning for problematic platforms
          if RUBY_PLATFORM.include?("mingw") && RUBY_VERSION < "3.5"
            Lutaml::Model::Logger.warn(
              "The Tomlib adapter may cause segmentation faults on Windows " \
              "with Ruby < 3.5 when parsing invalid TOML. Consider using the " \
              "TomlRB adapter instead.",
              __FILE__,
            )
          end

          def self.parse(toml, _options = {})
            Tomlib.load(toml)
          rescue StandardError => e
            # Tomlib can throw various errors for invalid TOML (TypeError,
            # ArgumentError, etc.).
            # Re-raise as Tomlib::ParseError which will be caught by serialize.rb
            raise Tomlib::ParseError, e.message
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

            Tomlib.dump(attributes_to_serialize)
            # Tomlib::Generator.new(to_h).toml_str
          end
        end
      end
    end
  end
end
