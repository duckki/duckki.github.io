# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "rouge-graphql-directives"
  spec.version = "0.1.0"
  spec.summary = "Teach Rouge 3.30 to highlight directives in GraphQL SDL"
  spec.authors = ["Duckki Oe"]
  spec.files = ["lib/rouge-graphql-directives.rb"]
  spec.require_paths = ["lib"]
  spec.add_runtime_dependency "rouge", "~> 3.30"
end
