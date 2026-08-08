---
title: "Auditing GraphQL Implementations With a Verified Model"
date: 2026-08-08 15:57:46 -0700
description: "A paired static audit shows how a Lean model can turn an open-ended GraphQL code review into a focused search for observable implementation differences."
tags:
  - GraphQL
  - Lean
  - Formal methods
  - Security
  - Code review
---

<!-- cspell:words GraphQL.js Grafast Hasura HotChocolate CoerceVariableValues gqlgen subselection -->

Can a formal model make an AI code auditor more effective? I tried a two-pass
audit of ten popular open-source GraphQL execution implementations.

Both passes were performed with GPT-5.6 Sol at Extra High reasoning effort. In
the initial pass, the model reviewed the implementations against the GraphQL
specification without access to my Lean models. In the follow-up, it audited the
same implementations with the
[Lean execution models](https://github.com/duckki/GraphQL.lean) as an additional
reference.

The follow-up found four confirmed deviations that the initial audit had missed.
This raised the finding count from 17 to 21. More importantly, it changed the
shape of the work: without Lean, the task was an open-ended code review. With
Lean, it became a focused implementation-difference review.

## Audit design

The audit followed execution ownership across project boundaries. Some popular
GraphQL servers delegate core execution to another package, so I counted the
implementation that actually performs field collection, resolver invocation,
value completion, and error propagation. The resulting comparison covers ten
execution implementations. GraphQL.js served as a behavioral reference and was
not scored as an audit target.

The scope was ordinary query and mutation execution. Parsing, transports,
subscriptions, incremental delivery, plugins, and other product-specific layers
were generally outside it. The review itself was a static source audit, not formal
verification of the implementations.

The two passes differed in one important input:

1. **Initial audit, without Lean:** review source against the English specification
   and the implementation's tests and architecture.
2. **Follow-up, with Lean:** revisit the same execution paths using explicit model
   obligations for variable coercion, field grouping, value completion, error
   propagation, and batch alignment.

Each reported deviation was confirmed with a minimal reproducer against the
affected implementation, while differential probes against GraphQL.js
established the expected reference behavior.

## Initial audit: without Lean

The initial pass found 17 deviations across the ten implementations.

| Implementation | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Juniper (0.17.1) | 3 | 2 | 0 |
| Hasura (2.49.5) | 2 | 1 | 0 |
| graphql-go (0.8.1) | 2 | 1 | 1 |
| Hot Chocolate (16.5.1) | 1 | 0 | 0 |
| Grafast (1.1.0) | 0 | 2 | 0 |
| graphql-java (26.0) | 0 | 0 | 1 |
| GraphQL Tools executor (1.5.7) | 0 | 0 | 1 |
| GraphQL.NET (8.8.4) | 0 | 0 | 0 |
| gqlgen (0.17.94) / graphql-core (3.2.11) *(two implementations)* | 0 | 0 | 0 |
| **Total** | **8** | **6** | **3** |

The initial review found no reportable deviation in GraphQL.NET, gqlgen, or
graphql-core.

## Follow-up: new Lean-guided findings

The second pass recorded only findings that were new relative to the initial
audit. It did not withdraw or reclassify any of the 17 initial findings.

| Implementation | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Juniper (0.17.1) | 0 | 0 | 0 |
| Hasura (2.49.5) | 0 | 0 | 0 |
| graphql-go (0.8.1) | 0 | 0 | 0 |
| Hot Chocolate (16.5.1) | 0 | 1 | 0 |
| Grafast (1.1.0) | 0 | 2 | 0 |
| graphql-java (26.0) | 0 | 0 | 0 |
| GraphQL Tools executor (1.5.7) | 0 | 0 | 0 |
| GraphQL.NET (8.8.4) | 0 | 1 | 0 |
| gqlgen (0.17.94) / graphql-core (3.2.11) *(two implementations)* | 0 | 0 | 0 |
| **Total** | **0** | **4** | **0** |

The Lean-guided pass found four additional medium-severity deviations in three
of ten implementations. Seven implementations produced no new reports. The
cumulative result was therefore 8 high, 10 medium, and 3 low findings: 21 in
total.

## What the model made easier to see

The four missed findings cluster around host-language values and error
handling:

- Grafast accepted an invalid concrete runtime type for an abstract field and
  returned `null` without a GraphQL field error.
- Grafast treated a batch result-count mismatch as a thrown host error rather than
  producing positional GraphQL field errors.
- GraphQL.NET and Hot Chocolate accepted a plain string as a list because .NET
  strings implement `IEnumerable<char>`. They completed characters as list items
  instead of reporting that the field result was not a list.

These are the kinds of bugs that are easy to overlook. A general review sees a
familiar iterable branch or an assertion about a batch API. The formal completion
model asks a much sharper question: *for this declared GraphQL type and this host
value shape, what observable result must be constructed?*

For a nullable list field, the relevant shape of the model is roughly:

```text
completeValue([T], value) =
  if value is a list:
    complete every item in order
  else:
    field error, then null at this response position
```

Once that branch is explicit, `string implements IEnumerable` is no longer an
incidental language detail. It is a possible violation of the `value is a list`
test. Similarly, the Lean model gives batch resolvers a precise contract: their
result sequence has the same cardinality and order as their source sequence. The
reviewer can then look directly for the mismatch branch and ask how it reaches the
GraphQL response.

The Lean model nicely complemented the GraphQL specification. It distilled the
relevant behavior into a smaller, executable set of cases: invalid list shapes,
invalid abstract values, field errors, null propagation, and positional batch
results. Those explicit cases narrowed the search.

## From broad review to implementation-difference review

Without a formal model, an audit begins with a large question: “Does this executor
follow the specification?” The specification is necessary, but it is prose, spread
across algorithms and definitions, and allows many implementation strategies.
Reviewers must first decide which details deserve attention.

With a formal model, the starting point is more mechanical:

1. Choose an observable obligation represented by the model.
2. Find the implementation branch that owns the corresponding state transition.
3. Compare the branch's possible outputs with the model's outputs.
4. Turn a mismatch into a minimal probe and a report with a trace back to the
   model.

This is not equivalence checking in the formal-methods sense. The implementations
were not translated into Lean, and the audit still requires human judgment about
architecture, version boundaries, and externally visible behavior. But it is a
useful middle ground: an implementation-difference review driven by a verified
reference model.

The first pass had already found many important issues: confusing an omitted
variable with an explicit `null`, resolving duplicate response names more than
once, losing required errors during non-null propagation, and violating serial
mutation behavior. The Lean pass confirmed several of those obligations as well.
Its new contribution was to focus attention on output-shape and batch-alignment
branches that looked like implementation details in the initial review.

## The value of theorems

One of the most useful lessons came from outside this audit corpus.

In another investigation, the buggy code was not in the implementation being
studied. It was at a call site. A Lean theorem had an explicit assumption that was
a precondition for the implementation's correct behavior. Reading that assumption
as an engineering contract led to a caller that did not establish it.

This is another benefit of a formal model backed by machine-checked theorems. A
theorem often has this shape:

```text
if precondition P holds, then implementation behavior has property Q
```

The theorem establishes `Q` only under `P`. Even without modeling the larger
codebase, `P` becomes an audit checklist item: where is it established, and
does it still hold at every call site?

This matters for security work. Many defects arise not from a broken algorithm in
isolation, but from a correct component invoked outside the conditions under which
its guarantees apply. Formalization makes those conditions more visible.

## Takeaway

This sequential audit produced a clear practical result: the Lean-guided second
pass found four semantic deviations missed by the initial specification-guided
pass. This showed that the formal model improved the effectiveness of AI code
review.

A Lean model can serve as a machine-checked blueprint for the software's intended
behavior. Its executable definitions tell the reviewer what the implementation
should do, while its theorems state which properties follow and under what
assumptions. That gives an AI reviewer authoritative guidance that documents and
tests alone rarely provide in such an explicit form.

I have seen the same pattern in other audits: an AI reviewer finds more issues
once it can compare production code with a formal model. That is not yet a
controlled scientific result, but it is a consistent and useful engineering
result. Formal models make AI code review more focused, explainable, and
effective, even when they abstract away implementation details.

Verifying the implementation directly is the gold standard, but this audit shows
how far one can go with an abstract model and machine-checked theorems in Lean.
Fuzzing can help bridge the remaining gap between the model and the implementation.
Even without fuzzing, Lean-guided AI code review is a practical engineering
technique that can be widely adopted.
