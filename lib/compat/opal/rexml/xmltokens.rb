# frozen_string_literal: false

module REXML
  module XMLTokens
    name_start_chars = [
      ":",
      "A-Z",
      "_",
      "a-z",
      "\\u00C0-\\u00D6",
      "\\u00D8-\\u00F6",
      "\\u00F8-\\u02FF",
      "\\u0370-\\u037D",
      "\\u037F-\\u1FFF",
      "\\u200C-\\u200D",
      "\\u2070-\\u218F",
      "\\u2C00-\\u2FEF",
      "\\u3001-\\uD7FF",
      "\\uF900-\\uFDCF",
      "\\uFDF0-\\uFFFD",
    ]

    name_chars = name_start_chars + [
      "\\-",
      "\\.",
      "0-9",
      "\\u00B7",
      "\\u0300-\\u036F",
      "\\u203F-\\u2040",
    ]
    NAME_START_CHAR = "[#{name_start_chars.join}]".freeze
    NAME_CHAR = "[#{name_chars.join}]".freeze
    NAMECHAR = NAME_CHAR

    ncname_start_chars = name_start_chars - [":"]
    ncname_chars = name_chars - [":"]
    NCNAME_STR = "[#{ncname_start_chars.join}][#{ncname_chars.join}]*".freeze
    NAME_STR = "(?:#{NCNAME_STR}:)?#{NCNAME_STR}".freeze

    NAME = "(#{NAME_START_CHAR}#{NAME_CHAR}*)".freeze
    NMTOKEN = "(?:#{NAME_CHAR})+".freeze
    NMTOKENS = "#{NMTOKEN}(\\s+#{NMTOKEN})*".freeze
    REFERENCE = "(?:&#{NAME};|&#\\d+;|&#x[0-9a-fA-F]+;)".freeze
  end
end
