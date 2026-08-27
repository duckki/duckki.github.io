---
title: "Proving GraphQL Query Inclusion in Lean"
date: 2026-08-18 00:00:00 -0700
description: "A semantics-first theory and verified decision procedure for deciding when one GraphQL query includes another."
tags:
  - GraphQL
  - Lean
  - Formal methods
  - Logic
---

<!-- cspell:words BoolCase coercibility coercible Formedness Martijn subselections Walraven -->

Suppose one GraphQL operation asks for everything another operation asks for,
and possibly more. Can we decide that relationship without executing either
operation?

This question appears in query-plan correctness checks, cache reuse, operation
comparison, and other static analyses. It sounds like a tree-subset test. A
small example shows why it is not.

Consider this small schema:

```graphql
interface Node {
  criticalStatus: String!
}

type User implements Node {
  criticalStatus: String!
  name: String
  profile: Profile
}

type Organization implements Node {
  criticalStatus: String!
  companyName: String
}

type Profile {
  bio: String
  avatarUrl: String
}

type Query {
  node: Node
}
```

Now compare these operations:

```graphql
query Provided($showLabel: Boolean!) {
  node {
    criticalStatus
    ... on User {
      label: name
      profile {
        bio
      }
    }
    ... on User {
      profile {
        avatarUrl
      }
    }
    ... on Organization {
      label: companyName @include(if: $showLabel)
    }
  }
}
```

```graphql
query Required($showLabel: Boolean!) {
  node {
    ... on User {
      label: name @include(if: $showLabel)
      profile {
        bio
        avatarUrl
      }
    }
    ... on Organization {
      label: companyName @include(if: $showLabel)
    }
  }
}
```

`Provided` includes `Required`, but not by literal tree containment. The two
`profile` occurrences in `Provided` merge by response name into the child
selection `{ bio avatarUrl }`. The runtime object type decides whether `label`
comes from `User.name` or `Organization.companyName`, while `$showLabel` decides
whether either occurrence is selected at all. Finally, if the extra non-null
`criticalStatus` field fails, null propagation can erase the entire `node`
object. That last case is why the semantic relation below compares only
error-free executions.

I recently added a query-inclusion theory to
[`graphql-lean`](https://github.com/duckki/graphql-lean). It contains:

- a semantic definition of inclusion over all error-free executions;
- an executable Boolean checker that does not materialize a normalized query;
- proofs that the checker is sound and complete against the stated definition; and
- a second, path-based definition proved equivalent to the former.

In short, the repo now has formalization of both the inclusion checker algorithm and what
we mean by *query inclusion*.

This work continues an earlier response-shape comparison algorithm that I wrote
for the
[`apollo-federation` crate](https://github.com/apollographql/router/blob/dev/apollo-federation/src/correctness/response_shape_compare.rs).
My colleague Derek Kuc presented that work in my place at GraphQLConf 2025 in
the lightning talk
[*Efficient Semantic Comparison of GraphQL Queries*](https://graphql.org/conf/2025/schedule/deac4044512d6d0a59c76aa712a777a4/?name=Lightning%20Talk:%20Efficient%20Semantic%20Comparison%20of%20GraphQL%20Queries%20-%20Derek%20Kuc,%20Apollo%20GraphQL).

## What does it mean for one query to include another?

Inclusion is directional. Call the larger operation `Provided` and the smaller
one `Required`:

```graphql
query Provided {
  character {
    id
    ... on Human {
      home
    }
  }
}
```

```graphql
query Required {
  character {
    id
  }
}
```

`Provided` includes `Required`: whenever `Required` selects a response field,
`Provided` selects the same field from the same resolver call. The reverse is
not true because `Required` does not select `home` in the `Human` case.

Equivalently, `Required` is a subset of `Provided`. I orient the relation as
[`includes schema provided required`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L121-L132)
because that reads naturally at call sites.

A tempting specification is to execute both operations and compare their plain
response values recursively with
[`responseValueIncludes`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L870-L892):

```lean
def responseValueIncludes : ResponseValue -> ResponseValue -> Prop
  | .object leftFields, .object rightFields =>
      ∀ rightName rightValue,
        (rightName, rightValue) ∈ rightFields
        -> ∃ leftValue,
            (rightName, leftValue) ∈ leftFields
            ∧ responseValueIncludes leftValue rightValue
  | .list leftValues, .list rightValues =>
      ∀ index rightValue,
        rightValues[index]? = some rightValue
        -> ∃ leftValue,
            leftValues[index]? = some leftValue
            ∧ responseValueIncludes leftValue rightValue
  | _, .object _ => False
  | _, .list _ => False
  | left, .null => left = .null
  | left, .scalar value => left = .scalar value
```

This says exactly what we want at first glance: every object field on the right
appears on the left, lists agree position by position, and leaves agree.

It was good enough for the first soundness proof. It was not strong enough for
completeness.

## A response can hide which resolver ran

Plain GraphQL responses contain response names and values, but not the field
name and arguments behind each value. Usually a resolver can expose that
difference by returning different data. There is, however, a boundary case
where valid nested fragments collect no child fields for any reachable runtime
type. Two different resolver calls can then both produce the same empty object:

```graphql
query Left {
  p: p1 {
    ... on T1 {
      ... on T2 {
        x
      }
    }
  }
}
```

```graphql
query Right {
  p: p2 {
    ... on T1 {
      ... on T2 {
        x
      }
    }
  }
}
```

Imagine that `p1` and `p2` both return interface `O`. `O` overlaps `T1`, and
`T1` overlaps `T2`, so each fragment spread is locally valid. But no concrete
object belongs to all three types. The nested selection therefore collects
nothing, and both error-free responses are always:

```json
{
  "p": {}
}
```

The response values are indistinguishable even though one query resolves `p1`
and the other resolves `p2`. This is the same pairwise-versus-global type
condition boundary discussed in
[When GraphQL Normalization Does Not Preserve Validation]({% post_url
2026-08-01-when-graphql-normalization-does-not-preserve-validation %}).

For query inclusion, resolver identity must be part of the meaning. I therefore
introduced
[`executeQueryAnnotated`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/AnnotatedExecution.lean#L254-L262).
Its
[`ResolvedFieldProvenance`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/AnnotatedExecution.lean#L26-L33)
and
[`AnnotatedResponseField`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/AnnotatedExecution.lean#L35-L49)
definitions record the concrete parent type, field name, original arguments,
and argument-coercion result behind each response field:

```lean
structure ResolvedFieldProvenance where
  parentType : Name
  fieldName : Name
  originalArguments : List Argument
  coercedArguments : ArgumentCoercionResult

inductive AnnotatedResponseField where
  | resolved
      (responseName : Name)
      (provenance : ResolvedFieldProvenance)
      (value : AnnotatedResponseValue)
```

The
[`annotatedResponseValueIncludes`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L79-L110)
relation matches response names,
[`sameFieldProvenance`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L60-L73),
list positions, and child values recursively. The annotated executor is a proof
instrument: it mirrors the spec-based executor but retains the information that
a plain JSON response erases.

## The semantic specification

With provenance available, the top-level definition remains small. It combines
[`sharedVariableDefinitionsSyntacticallyCompatible`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L30-L48)
with annotated execution:

```lean
def includes (schema : Schema) (left right : Operation) : Prop :=
  sharedVariableDefinitionsSyntacticallyCompatible left.variableDefinitions
    right.variableDefinitions
  ∧ ∀ (ObjectRef : Type) (resolvers : Resolvers ObjectRef)
      (variableValues : VariableValues) (source : ResolverValue ObjectRef),
      let leftResponse :=
        executeQueryAnnotated schema resolvers variableValues left source
      let rightResponse :=
        executeQueryAnnotated schema resolvers variableValues right source
      leftResponse.errors = 0
      -> rightResponse.errors = 0
      -> annotatedResponseValueIncludes leftResponse.data rightResponse.data
```

The definition quantifies over every resolver environment, variable assignment,
and root source. It adds two deliberate boundaries.

First, only pairs of error-free executions contribute an inclusion obligation.
Consider:

```graphql
query Provided {
  me {
    good
    bad # non-null
  }
}
```

```graphql
query Required {
  me {
    good
  }
}
```

Structurally, `Provided` includes `Required`. If `bad` fails, however, its
non-null error can bubble to `me`, while `Required` still returns an object
containing `good`. Static field inclusion does not imply response projection in
the presence of execution errors. Restricting the relation to error-free pairs
makes that boundary explicit.

Second, variable definitions shared by name must have the same declared types
and equivalent defaults. Definition order does not matter, and definitions that
occur on only one side are unrestricted. The shared check rejects this pair:

```graphql
query Left($enabled: Boolean = true) {
  age @include(if: $enabled)
}
```

```graphql
query Right($enabled: Boolean = false) {
  age @include(if: $enabled)
}
```

If `$enabled` is omitted, the two operations select different fields. Comparing
their selection syntax without comparing the shared defaults would be unsound.

## From a reference checker to an optimized checker

The first decision procedure,
[`includesBoolReference`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L239-L254),
is intentionally simple. It enumerates the Boolean assignments that can affect
either operation, explores every possible concrete runtime type, collects the
active field groups, and recursively compares merged child selection sets. Its
structure resembles [complete query normalization](https://github.com/duckki/graphql-lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/NormalForm.lean#L882).

The optimized
[`includesBool`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L760-L775)
checker keeps case splits over conditions local and incremental. It does not
normalize the operations or construct response shapes up front. Instead it:

1. flattens selections into conditioned fields;
2. groups that stream once by response name;
3. analyzes each required response name independently;
4. splits only the runtime-type regions and Boolean variables relevant to that
   response position; and
5. recursively compares merged children for composite fields.

Unlike the earlier response-shape implementation, this checker does not first
materialize and retain a normalized shape. Its response-local search delays
child conditions until recursion reaches the child scope and explores only the
regions relevant to each response name. This makes the optimized checker both
more direct and more efficient when the caller only needs an inclusion answer.

Simple cases avoid enumeration. Exact directional syntax inclusion is a
recursive shortcut. Scalar conditions are represented as conjunctions of
Boolean literals, so the checker can prove coverage symbolically.

For example, an unconditional field includes a conditional occurrence:

```graphql
query Provided {
  age
}
```

```graphql
query Required($enabled: Boolean!) {
  age @include(if: $enabled)
}
```

Complementary conditions also cover an unconditional requirement:

```graphql
query Provided($enabled: Boolean!) {
  age @include(if: $enabled)
  age @skip(if: $enabled)
}
```

```graphql
query Required {
  age
}
```

For every Boolean assignment, one of the two left occurrences is active.
GraphQL merges them under the same response name, so `Provided` includes
`Required`.

Type conditions are handled as regions rather than literal fragment syntax.
Think of the possible runtime types as pixels on a screen and each type
condition as an area drawn over that screen. Testing every object type
individually is like checking every pixel. The type-condition boundaries instead
partition the screen into regions. Every type within one region activates the
same guarded field occurrences, so the recursive search can compare that region
as a unit.

<figure class="type-region-figure">
  <picture>
    <source
      media="(max-width: 600px)"
      srcset="{{ '/assets/images/query-inclusion-type-regions-mobile.svg' | relative_url }}"
    >
    <img
      src="{{ '/assets/images/query-inclusion-type-regions.svg' | relative_url }}"
      alt="Comparison of an object-by-object search, which checks every type case, with a type-condition region search, which checks the four regions formed by two overlapping conditions."
      width="1200"
      height="560"
      loading="lazy"
    >
  </picture>
  <figcaption>
    Type conditions partition possible runtime types into regions with identical
    active selections. Comparing regions avoids repeating the same recursive
    sub-selection-set comparison for every object type.
  </figcaption>
</figure>

For example, a field selected under `Character` covers the same field required
only under `Human`, provided `Human` is a possible `Character` type:

```graphql
query Provided {
  character {
    ... on Character {
      id
    }
  }
}
```

```graphql
query Required {
  character {
    ... on Human {
      id
    }
  }
}
```

These examples are executable tests in the Lean repository, including positive
and negative direction checks, complementary directives, broader type regions,
different shared defaults, and aliases backed by different resolver calls.

## What is proved

The main soundness statement is
[`IncludesBoolSound`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L781-L789):

```lean
def IncludesBoolSound (schema : Schema) (left right : Operation) : Prop :=
  SchemaWellFormedness.schemaWellFormed schema
  -> Validation.operationDefinitionValid schema left
  -> Validation.operationDefinitionValid schema right
  -> includesBool schema left right = true
  -> includes schema left right
```

For a well-formed schema and valid operations, checker acceptance implies
semantic inclusion. This is the most important direction for a production
guard: a `true` result cannot silently accept an uncovered response position.

Completeness needs two additional non-vacuity conditions, captured by
[`IncludesBoolComplete`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L843-L857):

```lean
def IncludesBoolComplete (schema : Schema) (left right : Operation) : Prop :=
  SchemaWellFormedness.schemaWellFormed schema
  -> Validation.operationDefinitionValid schema left
  -> Validation.operationDefinitionValid schema right
  -> operationCompositeFieldTypesInhabited schema left
  -> operationCompositeFieldTypesInhabited schema right
  -> comparisonBranchesArgumentCoercible schema left right
  -> includes schema left right
  -> includesBool schema left right = true
```

[`operationCompositeFieldTypesInhabited`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L791-L826)
requires selected composite return types to have possible concrete object
types.
[`comparisonBranchesArgumentCoercible`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/QueryInclusion.lean#L828-L841)
requires an argument-coercible environment for each Boolean branch examined by
the checker.

These premises complement the error-free checks inside `includes`. The relation
ignores response pairs with execution errors, while the
completeness premises ensure that every syntactic comparison branch has an
error-free witness. Without them, semantic inclusion may hold vacuously because
a branch has no possible runtime object or cannot execute successfully.

Together, soundness and completeness say that `includesBool` decides the
semantic relation for well-formed schemas and valid, inhabited, argument-ready
operations. The checker itself is total on permissive raw syntax. Without the
inhabitance or coercibility premises, acceptance remains sound, but rejection
need not disprove semantic inclusion. A production API should check these
preconditions and return an inconclusive result rather than `false` when they
are not established.

## A second specification, without execution

The execution-based definition is intuitive: run both queries everywhere and
compare what they produce. But it is not the only useful view.

[Martijn Walraven's PR](https://github.com/duckki/graphql-lean/pull/1)
implements my earlier response-shape approach in Lean, based on the Apollo
Federation implementation. It decodes complete normal form into a
position-indexed response shape, connects the shape's denotation to field
collection, and provides proof-carrying subset and equivalence decisions. The PR
also introduced the concrete path definitions underlying that subset relation.
I wanted to prove that this smaller, path-based specification was equivalent to
the execution-based `includes` relation, without constructing a response shape
as an intermediate. I reused these definitions from the PR:
[`FieldHead`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/ResponsePath.lean#L23-L28)
and
[`PathStep`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/ResponsePath.lean#L30-L36).
Each step records:

- the concrete parent object type;
- the response name;
- the field name and arguments; and
- the field's output type.

[`operationSelectsPath`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/ResponsePath.lean#L77-L91)
holds when GraphQL field and subfield collection can walk a path under a
complete Boolean assignment. This gives a compact
[`ResponsePath.includes`](https://github.com/duckki/GraphQL.lean/blob/e62c87f4164415a073192ded1a2a78677f7c4749/GraphQL/Theories/ResponsePath.lean#L97-L112)
definition:

```lean
def includes (schema : Schema) (left right : Operation) : Prop :=
  QueryInclusion.sharedVariableDefinitionsSyntacticallyCompatible
    left.variableDefinitions right.variableDefinitions
  ∧ ∀ assignment,
      boolVarsComplete
        (QueryInclusion.comparisonConditionVariables
          left.selectionSet right.selectionSet)
        (boolCaseVariableValues assignment)
      -> ∀ path,
          operationSelectsPath schema right assignment path
          -> operationSelectsPath schema left assignment path
```

This version does not execute resolvers and does not compute an intermediate
response shape. It says directly: under every relevant Boolean assignment,
every concrete response path selected by the required operation is also
selected by the provided operation.

The two inclusion definitions agree. In the `ResponsePath` namespace, bare
`includes` is the path-based relation above, while `QueryInclusion.includes` is
the execution-based relation. The correspondence is stated directly as
[`IncludesSyntacticToSemantic` and
`IncludesSemanticToSyntactic`](https://github.com/duckki/GraphQL.lean/blob/98d447363beeaab7105e51958bf994d0172eece2/GraphQL/Theories/ResponsePath.lean#L122-L143):

```lean
def IncludesSyntacticToSemantic
    (schema : Schema) (left right : Operation) : Prop :=
  SchemaWellFormedness.schemaWellFormed schema
  -> Validation.operationDefinitionValid schema left
  -> Validation.operationDefinitionValid schema right
  -> includes schema left right
  -> QueryInclusion.includes schema left right

def IncludesSemanticToSyntactic
    (schema : Schema) (left right : Operation) : Prop :=
  SchemaWellFormedness.schemaWellFormed schema
  -> Validation.operationDefinitionValid schema left
  -> Validation.operationDefinitionValid schema right
  -> QueryInclusion.operationCompositeFieldTypesInhabited schema left
  -> QueryInclusion.operationCompositeFieldTypesInhabited schema right
  -> QueryInclusion.comparisonBranchesArgumentCoercible schema left right
  -> QueryInclusion.includes schema left right
  -> includes schema left right
```

The first statement turns path inclusion into execution-based inclusion for a
well-formed schema and valid operations. The reverse statement adds the
inhabitance and argument-coercibility premises needed to rule out vacuous
executions as in the `IncludesBoolComplete` statement above.

This correspondence is valuable beyond having another theorem. The two
definitions approach the same concept from opposite directions. One starts
from observable execution with resolver provenance. The other starts from
field collection and concrete paths. Proving their agreement checks that
neither view has silently omitted aliases, arguments, runtime types, Boolean
conditions, field merging, or recursive child selections.

## What the formalization changed

Implementing the checker was not the hard part. The hard part was discovering
the exact relation the checker could decide and the premises each theorem
required.

The failed completeness proof exposed that plain responses lose resolver provenance. Null
bubbling and argument coercion exposed why response projection needs a
successful-execution precondition. Defaults exposed why the same shared variable
definitions are needed in the relation. Empty composite types exposed where semantic
inclusion can become vacuous.

The finished theory now describes query inclusion in three mutually reinforcing
ways: a semantic relation over annotated executions, a smaller syntactic
relation over concrete response paths, and an executable checker proved sound
and complete against both views. Each form serves a different purpose. Execution
explains the meaning, paths expose the essential structure, and the checker
makes the theory usable.

The optimized checker was also ported to Rust and tested differentially against
a native Lean oracle. The complete 26,880-case modeled corpus produced exact
agreement, while a separate full-GraphQL lane checks that named fragments behave
like their inlined equivalents. The Lean checker is machine-proved; the fuzzing
provides strong behavioral evidence that the Rust port matches it over the
exercised domain. The resulting implementation is also more efficient than my
original 2025 response-shape algorithm.

For query inclusion, the result is more than a function. It is a checked account
of what inclusion means, the conditions under which it can be decided, and a
practical algorithm for deciding it.
