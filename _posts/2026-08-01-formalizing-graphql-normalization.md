---
title: "Formalizing GraphQL and Proving Query Normalization in Lean"
date: 2026-08-01 00:00:00 -0700
description: "A Lean formalization of GraphQL execution, plus proofs that directive-aware query normalization preserves semantics and produces a canonical form."
tags:
  - GraphQL
  - Lean
  - Formal methods
  - Query languages
---

<!-- cspell:words Hartig Pérez Díaz Olmedo Tanter Formedness -->

I have been working on [`graphql-lean`](https://github.com/duckki/graphql-lean),
a formalization of GraphQL in the [Lean theorem prover](https://lean-lang.org/).
It is based on the
[GraphQL September 2025 specification](https://spec.graphql.org/September2025/).

By "formalization," I mean that I translated a scoped part of the English
specification into Lean data types, functions, and predicates. Schemas and
operations are data. Schema validity and operation validation are
predicates. Field collection, value completion, error propagation, and query
execution are functions. Claims about those definitions are theorems checked by
Lean.

The project has several results, but this post focuses on query normalization:

- Normalization is semantics-preserving: running a normalized query produces
  the same response as running the original query.
- Normal form is semantically canonical: two normal queries with the same
  meaning must have the same syntax, modulo ordering that execution does not
  observe.
- The complete normalizer handles GraphQL's built-in `@skip` and `@include`
  directives. The earlier formal-semantics paper and previous mechanized
  GraphQL formalization did not model directives.

The last two points are the interesting ones. Preserving meaning is necessary,
but canonicity says that each meaning has a unique normal representation.

## What part of GraphQL is formalized?

The model covers query execution for a substantial plain-GraphQL fragment:

- object, interface, union, enum, scalar, input object, list, and non-null types;
- schema validity checks and operation validation;
- variables and operation variable defaults;
- fields, aliases, inline fragments, and a separate verified layer for named
  fragments and fragment spreads;
- the built-in executable directives `@skip` and `@include`;
- field collection and grouped field execution;
- nullable, non-null, and list completion;
- null bubbling and execution errors, represented up to their count.

It does not try to cover the entire GraphQL ecosystem. Mutations,
subscriptions, custom directives, introspection, transport, asynchronous
scheduling, and full input and result coercion are outside the current scope.
Detailed error messages, paths, and locations are abstracted to an error count.
The complete boundary is documented in the project's
[spec conformance summary](https://github.com/duckki/graphql-lean/blob/main/docs/spec-conformance.md).

The execution model is *resolver-parametric*. It does not assume a particular
database or graph representation. Runtime objects are opaque references owned
by an arbitrary resolver environment. This lets semantic equivalence quantify
over every resolver implementation without assumptions about the underlying
dataset.

Roughly, two operations are semantically equivalent when they produce equivalent
full responses for every resolver environment, variable assignment, execution
fuel, and root object reference. Here is the Lean definition:

```lean
def operationsSemanticallyEquivalent (schema : Schema) (left right : Operation) : Prop :=
  ∀ {ObjectRef : Type} (resolvers : Resolvers ObjectRef)
      variableValues fuel (rootObj : ResolverValue ObjectRef),
    Response.semanticEquivalent
      (executeQueryWithFuel schema resolvers variableValues left fuel rootObj)
      (executeQueryWithFuel schema resolvers variableValues right fuel rootObj)
```

- `Response.semanticEquivalent` compares responses without treating object-field
  order as meaningful.
- `fuel` is an explicit recursion budget for the bounded execution model. It
  makes induction over execution possible, and equivalence compares both
  operations at the same fuel value.

## Why normalize a GraphQL query?

Different GraphQL syntax can describe the same execution. A field may occur more
than once with the same response name. Selections may be nested under inline
fragments in different orders. Some inline fragments repeat a type condition or
add no constraint at all.

This project has two layers of normal form.

### Ground-type normal form

Assume `Character` is an interface implemented by `Human` and `Droid`, `search`
returns `Character`, and `friends` also returns `Character`. This query contains
duplicate fields, overlapping interface and object conditions, and a redundant
nested `Human` condition:

```graphql
query {
  search {
    id
    id
    ... on Character {
      name
      friends {
        id
      }
    }
    ... on Human {
      homePlanet
      friends {
        name
      }
      ... on Human {
        homePlanet
        friends {
          id
        }
      }
    }
  }
}
```

One normalized version is:

```graphql
query {
  search {
    ... on Human {
      id
      name
      homePlanet
      friends {
        ... on Human {
          id
          name
        }
        ... on Droid {
          id
          name
        }
      }
    }
    ... on Droid {
      id
      name
      friends {
        ... on Human {
          id
        }
        ... on Droid {
          id
        }
      }
    }
  }
}
```

The directive-free normalizer performs two main transformations:

1. It merges fields with the same response name. Their child selection sets are
   merged into one representative field.
2. It grounds abstract return types. Selections under an interface or union are
   expanded into inline fragments for the possible concrete object types.

The result has no redundant sibling response names or type-condition branches.

In the example, the two `id` selections collapse into one. The two `homePlanet`
selections also collapse. All `friends` selections for a concrete parent type
are merged before their abstract `Character` result is grounded recursively into
`Human` and `Droid` branches.

Normal form has vastly simpler structure: The root selection sets and every field's
selection set can have up to one level of inline spreads (conditioned on an object type).
If the field's output type is an object type already, then its selection set can have
field selections only. This simpler structure helps prove properties of execution. More
surprisingly, it also gives a finite representation of semantic equivalence, as the
canonicity result below shows.

Ground-typed normal form was introduced in
[Hartig and Pérez's *Semantics and Complexity of GraphQL*](https://doi.org/10.1145/3178876.3186014).
[Díaz, Olmedo, and Tanter's *A Mechanized Formalization of GraphQL*](https://doi.org/10.1145/3372885.3373822)
then gave an algorithmic normalizer and proved its correctness and semantic
preservation in Coq. The ground layer in this project follows that broad
construction for a resolver-parametric execution model.

### Complete normal form

The complete normalizer adds `@skip` and `@include`. These directives make a
query denote different directive-free queries under different Boolean variable
assignments.

For example:

```graphql
query Hero($x: Boolean!, $y: Boolean!) {
  hero {
    id
    name @include(if: $x)
    homePlanet @skip(if: $y)
  }
}
```

This operation has four Boolean cases, each with a different directive-free
body:

| `$x` | `$y` | Fields under `hero` |
| --- | --- | --- |
| `false` | `false` | `id`, `homePlanet` |
| `false` | `true` | `id` |
| `true` | `false` | `id`, `name`, `homePlanet` |
| `true` | `true` | `id`, `name` |

The complete normalizer finds all Boolean variables used by the directives and
enumerates their complete assignments once, at the operation root. Each nonempty
case becomes a branch guarded by a chain of anonymous inline fragments with
directives. Inside a branch, the directives have been evaluated away and the
body is in ground-type normal form.

Conceptually, consider the `$x = true`, `$y = true` case. First, its complete
assignment is encoded as root-level directive guards:

```graphql
query Hero($x: Boolean!, $y: Boolean!) {
  ... @include(if: $x) {
    ... @include(if: $y) {
      hero {
        id
        name @include(if: $x)
        homePlanet @skip(if: $y)
      }
    }
  }
}
```

Then selections that cannot execute under those guards are removed:

```graphql
query Hero($x: Boolean!, $y: Boolean!) {
  ... @include(if: $x) {
    ... @include(if: $y) {
      hero {
        id
        name
      }
    }
  }
}
```

Here, `homePlanet @skip(if: $y)` cannot execute under the
`... @include(if: $y)` guard, so it disappears. The `name` directive is known to
pass and is removed from the branch body.

Repeating this process for every assignment yields the complete normal form:

```graphql
query Hero($x: Boolean!, $y: Boolean!) {
  ... @skip(if: $x) {
    ... @skip(if: $y) {
      hero {
        id
        homePlanet
      }
    }
  }
  ... @skip(if: $x) {
    ... @include(if: $y) {
      hero {
        id
      }
    }
  }
  ... @include(if: $x) {
    ... @skip(if: $y) {
      hero {
        id
        name
        homePlanet
      }
    }
  }
  ... @include(if: $x) {
    ... @include(if: $y) {
      hero {
        id
        name
      }
    }
  }
}
```

In logic terms, the root becomes a complete Boolean disjunctive normal form.
The normalizer does not create another exponential Boolean tree inside every
nested field; it passes the selected root case down while normalizing the child
selection sets.

The example above is not just illustrative. The repository contains an
[executable snapshot test](https://github.com/duckki/graphql-lean/blob/main/Tests/GraphQL/Theories/NormalForm/CompleteNormalization.lean)
for exactly these four branches, along with execution tests comparing the source
and normalized operations.

## Proving that normalization preserves meaning

For a well-formed schema and a valid operation, the main complete-normalization
preservation result has this shape:

```lean
def completeNormalizationSemanticsPreserved (schema : Schema) (operation : Operation)
    : Prop :=
  SchemaWellFormedness.schemaWellFormed schema
  -> Validation.operationDefinitionValid schema operation
  -> ∀ {ObjectRef : Type} (resolvers : Resolvers ObjectRef)
        variableValues fuel (rootObj : ResolverValue ObjectRef),
      operationBoolVarsComplete operation variableValues
      -> executeQueryWithFuel schema resolvers variableValues operation
            fuel rootObj
          = executeQueryWithFuel schema resolvers variableValues
              (completeNormalizeOperation schema operation) fuel rootObj
```

The equality holds for arbitrary resolvers and root object values when every
Boolean variable used by `@skip` or `@include` has a Boolean runtime value.

Semantics preservation gives the familiar compiler-correctness statement:
normalization does not change the response.

## Semantic canonicity

Let `N(q)` be the normal form of a query. Let `q1 ~= q2` mean semantic equivalence
(`operationsSemanticallyEquivalent` above), and let `=r` mean syntactic equality up to the
reorderings that GraphQL execution does not observe. The main result is schematically:

```text
q1 ~= q2  <->  N(q1) =r N(q2)
```

This is a schematic summary. The Lean definition states the two directions separately
because their smallest assumption sets differ.

In particular, complete source-level soundness is stated for environments that
assign every Boolean directive variable and for operations with matching
variable definitions and Boolean support. The uniqueness direction additionally
names the possible-type and Boolean/type-condition feasibility conditions needed
for normalization to preserve valid, nonempty syntax.

The reverse (`<-`) direction is syntactic soundness:

```text
N(q1) =r N(q2)  ->  q1 ~= q2
```

If the normal forms match, the original queries mean the same thing. This is the
comparatively direct direction: equality up to reordering is sound for execution,
and normalization preserves the source operations' semantics.

The forward (`->`) direction is uniqueness, or semantic completeness:

```text
q1 ~= q2  ->  N(q1) =r N(q2)
```

Semantically equivalent queries cannot retain a meaningful syntactic difference
after normalization. This direction is much harder because execution appears to
throw the original syntax away.

The ground-type proof proceeds by contrapositive. If two valid normal selection
sets differ, it identifies a concrete response path where they differ and then
constructs resolvers and source objects that make the difference observable. A
simple mismatch such as selecting `id` on one side and `name` on the other can be
separated by a resolver returning distinct values. For a nested mismatch, the
proof constructs object values along the path until execution reaches the
differing selection.

In outline:

```text
different normal syntax
  -> an observable response path
  -> resolvers and source objects exposing that path
  -> different responses
```

Therefore, operations that no resolver environment can distinguish cannot have
different normal forms.

Complete normalization adds one step. A Boolean assignment activates exactly
one root branch. Matching directive guards pass, while non-matching guards
collect no fields. This isolates a directive-free ground-normal body on each
side, where the ground uniqueness theorem applies. Repeating the argument pairs
all Boolean branches up to reordering.

This is stronger than semantic preservation alone. The earlier
[GraphCoQL](https://github.com/imfd/GraphCoQL) mechanization proved that its
ground normalizer preserved semantics, but its query language did not include
variables or directives, and it did not prove this semantic-uniqueness
direction. To my knowledge, this is the first mechanized proof that normal
GraphQL operations are uniquely determined by resolver-parametric execution
semantics, and the first such result for a normalizer covering `@skip` and
`@include`.

Semantic canonicity reduces equivalence—which quantifies over arbitrary
resolvers and inputs—to three finite steps:

```text
1. Normalize the first operation.
2. Normalize the second operation.
3. Compare the normal forms up to permitted reordering.
```

The normalizers are total deterministic Lean functions. The current reordering
relations are propositions, not yet packaged as a verified executable
comparator. Adding that comparator, or a verified sorting pass that chooses one
concrete order, would turn the theorem into a directly executable decision
procedure.

## Conclusion

The [GraphQL specification](https://spec.graphql.org/September2025/) gives a
detailed execution algorithm in English. Translating its scoped core into Lean
makes the algorithms executable, the invariants explicit, and the claims
machine-checkable.

The inclusion of `@skip` and `@include` matters because the built-in conditional
selection semantics are now part of the theorem instead of being assumed away.

For normalization, the result goes beyond proving that a rewrite is safe. The
normal form is a complete semantic invariant, modulo irrelevant ordering:

```text
same meaning  <->  same normal form
```

This formal model is also the foundation for the next results I plan to write
about: alternative GraphQL execution strategies, proved equivalent to the
specification-facing executor.
