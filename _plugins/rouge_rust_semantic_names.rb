# frozen_string_literal: true

require "rouge"
require "set"

rust = Rouge::Lexers::Rust
tokens = Rouge::Token::Tokens

# Rouge already recognizes most Rust syntax well. Add declaration names, which
# its stock lexer otherwise leaves as generic identifiers.
rust.prepend(:root) do
  rule %r/(\b(?:enum|struct|trait|type|union))([ \t]+)([A-Za-z_][A-Za-z0-9_]*)/ do
    groups(tokens::Keyword::Declaration, tokens::Text, tokens::Name::Entity)
  end
end

# Apply a small, consistent identifier palette. Known locals are blue, fields
# and methods are yellow, and unresolved/open names keep Rouge's neutral white.
module RougeRustSemanticNames
  IDENTIFIER = /[A-Za-z_][A-Za-z0-9_]*/
  GENERIC_NAME = Rouge::Token::Tokens::Name
  FUNCTION_NAME = Rouge::Token::Tokens::Name::Function
  PROPERTY_NAME = Rouge::Token::Tokens::Name::Property
  LOCAL_NAME = Rouge::Token::Tokens::Name::Variable
  FIELD_NAME = Rouge::Token::Tokens::Name::Attribute
  PUNCTUATION = Rouge::Token::Tokens::Punctuation

  def stream_tokens(source)
    local_names = rust_local_names(source)
    field_names = source.scan(/^[ \t]+(?:pub(?:\([^)]*\))?\s+)?(#{IDENTIFIER})\s*:/).flatten.to_set

    super(source) do |token, value|
      if [FUNCTION_NAME, PROPERTY_NAME].include?(token) && value.start_with?(".")
        yield PUNCTUATION, "."
        yield FIELD_NAME, value.delete_prefix(".")
      elsif local_names.include?(value) && token == GENERIC_NAME
        yield LOCAL_NAME, value
      elsif field_names.include?(value) && token == GENERIC_NAME
        yield FIELD_NAME, value
      else
        yield token, value
      end
    end
  end

  private

  def rust_local_names(source)
    names = Set.new

    source.scan(/\blet\s+(?:mut\s+)?([^=;]+?)\s*=/) do |binding|
      names.merge(binding[0].split(":", 2).first.scan(IDENTIFIER))
    end
    source.scan(/\bfn\s+#{IDENTIFIER}(?:<[^>]*>)?\s*\((.*?)\)\s*(?:->|where|\{)/m) do |parameters|
      parameters[0].scan(/(?:\A|,)\s*(?:&\s*)?(?:mut\s+)?(#{IDENTIFIER})\s*:/) do |name|
        names << name[0]
      end
    end
    source.scan(/\bfor\s+(#{IDENTIFIER})\s+in\b/) { |name| names << name[0] }
    source.scan(/\|([^|]+)\|/) { |parameters| names.merge(parameters[0].scan(IDENTIFIER)) }

    names.delete_if { |name| %w[_ mut ref self].include?(name) }
    names
  end
end

Module.instance_method(:prepend).bind_call(rust, RougeRustSemanticNames)
