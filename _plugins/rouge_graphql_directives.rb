# frozen_string_literal: true

require "rouge"

# Rouge recognizes directives in GraphQL operations, but not after schema
# definitions or field types. Reuse its existing directive and argument rules in
# the missing SDL states so constructs such as `String @cost(weight: "2")` are
# tokenized normally instead of marking the remainder of the block as an error.
graphql = Rouge::Lexers::GraphQL

%i[root type_definition type_definition_set].each do |state|
  graphql.prepend(state) do
    mixin :has_directives
  end
end

# Keep GraphQL identifiers visually consistent without attempting schema-aware
# highlighting. GraphQL's usual capitalization and punctuation conventions are
# enough to distinguish types, fields, arguments, and directives.
module RougeGraphQLSemanticNames
  DECLARATION_KEYWORDS = %w[
    enum fragment input interface mutation query scalar schema subscription
    type union
  ].freeze

  GENERIC_NAME = Rouge::Token::Tokens::Name
  KEYWORD = Rouge::Token::Tokens::Keyword
  TYPE_NAME = Rouge::Token::Tokens::Name::Class
  ARGUMENT_NAME = Rouge::Token::Tokens::Name::Attribute
  ALIAS_NAME = Rouge::Token::Tokens::Name::Label
  DECLARATION_NAME = Rouge::Token::Tokens::Name::Entity
  DIRECTIVE_NAME = Rouge::Token::Tokens::Name::Decorator

  def stream_tokens(source)
    source_tokens = []
    super(source) { |token, value| source_tokens << [token, value] }

    previous_significant = nil
    parenthesis_depth = 0

    source_tokens.each_with_index do |(token, value), index|
      following = source_tokens[(index + 1)..].reject { |_, candidate| candidate.match?(/\A\s*\z/) }
      next_token, next_value = following[0]
      after_next_token, after_next_value = following[1]

      replacement = if token == KEYWORD && value.start_with?("@")
                      DIRECTIVE_NAME
                    elsif token == GENERIC_NAME && DECLARATION_KEYWORDS.include?(previous_significant)
                      DECLARATION_NAME
                    elsif token == GENERIC_NAME && value.match?(/\A[A-Z]/)
                      TYPE_NAME
                    elsif token == GENERIC_NAME && parenthesis_depth.positive? && next_value == ":"
                      ARGUMENT_NAME
                    elsif token == GENERIC_NAME && parenthesis_depth.zero? && next_value == ":" &&
                          after_next_token == GENERIC_NAME && after_next_value.match?(/\A[a-z_]/)
                      ALIAS_NAME
                    else
                      token
                    end

      parenthesis_depth += 1 if value == "("
      parenthesis_depth -= 1 if value == ")"
      previous_significant = value unless value.match?(/\A\s*\z/)
      yield replacement, value
    end
  end
end

Module.instance_method(:prepend).bind_call(graphql, RougeGraphQLSemanticNames)
