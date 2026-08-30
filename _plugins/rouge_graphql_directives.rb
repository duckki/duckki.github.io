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
