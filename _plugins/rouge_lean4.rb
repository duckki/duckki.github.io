# frozen_string_literal: true

require "rouge"
require "set"

# Rouge's bundled lexer targets Lean 3. Extend it with the Lean 4 constructs
# used throughout the blog, and emit semantic token classes where lexical
# context makes that distinction reliable.
lean = Rouge::Lexers::Lean

lean.keywords.merge(%w[
  abbrev
  class
  decreasing_by
  deriving
  do
  else
  for
  forall
  if
  in
  let
  macro
  mutual
  nomatch
  noncomputable
  partial
  return
  structure
  syntax
  termination_by
  then
  unless
  unsafe
  where
])

comment_doc = Rouge::Token::Tokens::Comment::Doc
comment_multiline = Rouge::Token::Tokens::Comment::Multiline
comment_single = Rouge::Token::Tokens::Comment::Single
keyword = Rouge::Token::Tokens::Keyword
keyword_declaration = Rouge::Token::Tokens::Keyword::Declaration
keyword_type = Rouge::Token::Tokens::Keyword::Type
name_attribute = Rouge::Token::Tokens::Name::Attribute
name_decorator = Rouge::Token::Tokens::Name::Decorator
name_entity = Rouge::Token::Tokens::Name::Entity
name_function = Rouge::Token::Tokens::Name::Function
name_namespace = Rouge::Token::Tokens::Name::Namespace
name = Rouge::Token::Tokens::Name
operator = Rouge::Token::Tokens::Operator
punctuation = Rouge::Token::Tokens::Punctuation
text = Rouge::Token::Tokens::Text

lean.prepend(:root) do
  rule %r/\/-!.*?-\//m, comment_doc
  rule %r/\/-.*?-\//m, comment_multiline
  rule %r/--.*?$/, comment_single

  rule %r/(\b(?:structure|class|inductive))([ \t]+)([\p{L}_][\p{L}\p{N}_'!?]*)/ do
    groups(keyword_declaration, text, name_entity)
  end
  rule %r/(\b(?:abbrev|def|lemma|opaque|theorem))([ \t]+)([\p{L}_][\p{L}\p{N}_'!?]*)/ do
    groups(keyword_declaration, text, name_function)
  end

  rule %r/@\[[^\]]+\]/, name_decorator
  rule %r/([\p{Lu}][\p{L}\p{N}_'!?]*)(\.)([\p{L}_][\p{L}\p{N}_'!?]*)/ do
    groups(name_namespace, punctuation, name_attribute)
  end
  rule %r/(\.)([\p{L}_][\p{L}\p{N}_'!?]*)/ do
    groups(punctuation, name_attribute)
  end
  rule %r/[∀λ]/, keyword
  rule %r/#?[\p{L}_][\p{L}\p{N}_'!?]*/ do |match|
    identifier = match[0]
    if lean.keywords.include?(identifier)
      token keyword
    elsif lean.types.include?(identifier)
      token keyword_type
    else
      token name
    end
  end

  rule %r/[{}()\[\],]/, punctuation
  rule %r/\./, punctuation
  rule %r/:=|=>|->|<-|→|←|↔|≤|≥|≠|∈|=|\+|-|\*|\/|\?|⟨|⟩/, operator
end

module RougeLean4SemanticNames
  IDENTIFIER = /[\p{L}_][\p{L}\p{N}_'!?]*/
  GENERIC_NAME = Rouge::Token::Tokens::Name
  TYPE_NAME = Rouge::Token::Tokens::Name::Class
  LOCAL_NAME = Rouge::Token::Tokens::Name::Variable
  FIELD_NAME = Rouge::Token::Tokens::Name::Attribute

  def stream_tokens(source)
    local_names = lean4_local_names(source)
    field_names = source.scan(/^\s{2,}(#{IDENTIFIER})\s*:/).flatten.to_set

    super(source) do |token, value|
      replacement = if local_names.include?(value) && [GENERIC_NAME, TYPE_NAME].include?(token)
                      LOCAL_NAME
                    elsif field_names.include?(value) && token == GENERIC_NAME
                      FIELD_NAME
                    else
                      token
                    end
      yield replacement, value
    end
  end

  private

  def lean4_local_names(source)
    names = Set.new

    source.scan(/[({]\s*([^:(){}\n]+?)\s*:/) do |segment|
      names.merge(segment[0].scan(IDENTIFIER))
    end
    source.scan(/(?:∀|∃|\bfun\b)\s+(#{IDENTIFIER}(?:\s+#{IDENTIFIER})*)\s*(?:,|=>|→)/) do |segment|
      names.merge(segment[0].scan(IDENTIFIER))
    end
    source.scan(/\blet\s+(#{IDENTIFIER})/) { |name| names << name[0] }
    source.scan(/\bfor\s+(#{IDENTIFIER})\s+in\b/) { |name| names << name[0] }
    source.scan(/^\s*\|(.+?)(?:=>|→)/) do |pattern|
      unqualified = pattern[0].gsub(/\.#{IDENTIFIER}/, "")
      names.merge(unqualified.scan(IDENTIFIER))
    end

    names.merge(source.scan(/\b[\p{Ll}]\b/).flatten)
    names.delete_if { |name| name == "_" || self.class.keywords.include?(name) }
    names
  end
end

Module.instance_method(:prepend).bind_call(lean, RougeLean4SemanticNames)
