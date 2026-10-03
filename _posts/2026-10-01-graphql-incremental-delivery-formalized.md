---
layout: post
title: "Formally Verified GraphQL Incremental Delivery"
date: 2026-10-01 00:00:00 -0700
description: "Formalizing GraphQL incremental delivery in Lean exposed a missing WorkQueue contract, produced correctness proofs, and uncovered bugs in GraphQL.js."
tags:
  - Software engineering
  - GraphQL
  - Lean
  - Formal methods
  - AI
---

<!-- Code citations use graphql-lean commit c64eecf35458801dade61a1c9c7c46afc0419a3c.
     Upstream PR status checked on 2 October 2026. -->

<!-- cspell:words Prove2Me hasNext WorkQueue GraphQL conforming conformance defer resolvers subfields -->

Long-awaited GraphQL incremental delivery landed in [GraphQL.js v17][v17] as an
experimental feature, while its specification is still a [draft][spec-pr].
Ordinary GraphQL returns one JSON tree. Incremental delivery lets the server return
part of the requested data now, then send deferred fields and streamed list items later.

For example, a client can ask for a user's ID immediately, their biography
later, and the first friend before the rest of the list is ready:

```graphql
{
  user {
    id
    ... @defer(label: "profile") { biography }
    friends @stream(initialCount: 1, label: "friends") { name }
  }
}
```

One possible delivery looks like this:

<figure class="incremental-figure">
  <div class="incremental-panel">
    <div class="incremental-kicker">One query · data arrives in pieces</div>
    <div class="incremental-cards">
      <div class="incremental-card incremental-card--blue">
        <span class="incremental-step">Now</span>
        <h3>Initial response</h3>
        <div class="incremental-code">id: "42"<br>friends[0]: Ada</div>
        <p>Announce pending IDs for profile and friends.</p>
      </div>
      <div class="incremental-card incremental-card--teal">
        <span class="incremental-step">Later · @defer</span>
        <h3>Profile patch</h3>
        <div class="incremental-code">biography:<br>"Builds compilers."</div>
        <p>Use the profile ID, then mark it complete.</p>
      </div>
      <div class="incremental-card incremental-card--gold">
        <span class="incremental-step">Later · @stream</span>
        <h3>Next list item</h3>
        <div class="incremental-code">friends[1]: Grace</div>
        <p>Use the friends ID, then complete it when the stream ends.</p>
      </div>
    </div>
    <div class="incremental-connector">↓ Merge the delivered pieces</div>
    <div class="incremental-result incremental-code">user: { id: "42", biography: "Builds compilers.", friends: [Ada, Grace] }</div>
  </div>
  <figcaption>Ordinary GraphQL returns a tree. Incremental GraphQL returns a protocol for constructing that tree over time. Data is abbreviated here; actual responses contain JSON objects.</figcaption>
</figure>

The server announces pending delivery IDs, sends patches that refer to those
IDs, and eventually marks them complete. Those two later deliveries might
arrive in the opposite order, or together in one update. The client still needs
to assemble the same response.

I had already verified variations of GraphQL execution in
[Lean][lean], a programming language and proof assistant. I expected to
formalize and verify this extension in a few days as a side project. It took seventeen!
The changes to the initial execution were manageable. The difficult part was tracking
work that had finished computing but could not yet be delivered.

The result is a [formal model of incremental execution][execution],
a [work queue contract][queue-contract], [general correctness proofs][theorem-guide],
and a [work queue implementation model][queue-model] based on the GraphQL.js code.

## Much larger than ordinary execution

At first, incremental delivery looks like a small extension. Collect fields,
decide which ones can wait, execute the initial selection, and hand the rest to
a queue. For `@stream`, keep the requested list prefix in the initial response
and deliver the remaining items later.

The core incremental execution module is only 16% longer than the ordinary execution
module. But execution also needs a model of remaining work, its permitted
delivery histories, response observations, and the concrete queue algorithm that
produces them.

Here is the size of this development at the [merged commit][snapshot],
including comments and blank lines:

| Surface | Ordinary execution | Incremental delivery |
| --- | ---: | ---: |
| Core execution definitions | 928 lines | 1,077 lines |
| Execution plus work queue definitions | n/a | 4,048 lines |

The second row totals all seven incremental delivery modules, covering both
specification and implementation. Ordinary execution has no corresponding work queue.
These are source-line measurements of this Lean project, not the size of the
GraphQL specification or the JavaScript implementation.

<figure class="incremental-figure">
  <div class="incremental-panel incremental-chart">
    <div class="incremental-kicker">Definitions · comments and blank lines included</div>
    <div class="incremental-bar-label"><span>Ordinary execution</span><strong>928 lines</strong></div>
    <div class="incremental-bar-track" aria-hidden="true"><span class="incremental-fill--blue" style="width: 22.925%"></span></div>
    <div class="incremental-bar-label"><span>Incremental execution</span><strong>4,048 lines</strong></div>
    <div class="incremental-bar-track" aria-hidden="true">
      <span class="incremental-fill--blue" style="width: 26.606%"></span><span class="incremental-fill--teal" style="width: 18.997%"></span><span class="incremental-fill--gold" style="width: 30.435%"></span><span class="incremental-fill--purple" style="width: 23.962%"></span>
    </div>
    <dl class="incremental-legend">
      <div><dt><i class="incremental-fill--blue"></i>Execution</dt><dd>1,077 lines</dd></div>
      <div><dt><i class="incremental-fill--teal"></i>Queue semantics</dt><dd>769 lines</dd></div>
      <div><dt><i class="incremental-fill--gold"></i>Concrete queue</dt><dd>1,232 lines</dd></div>
      <div><dt><i class="incremental-fill--purple"></i>Other supporting definitions</dt><dd>970 lines</dd></div>
    </dl>
  </div>
  <figcaption>The core execution definition grew by 16%. Describing the remaining work and its delivery protocol added several more layers.</figcaption>
</figure>

That expansion pointed to a question I had underestimated: what must the queue
promise so that the response protocol is correct?

## The missing WorkQueue contract

The [draft specification][spec-execution] calls `CreateWorkQueue(work)`, but
leaves its algorithm and complete behavioral requirements unspecified. To
prove the surrounding execution correct, we need to say which output histories
that queue is allowed to produce.

“Put the remaining tasks in a queue” is insufficient. A task may contribute to
several deferred fragments, so its value must be delivered once without losing
track of any fragment. Nested work may have to wait for its parent, streams
can reveal more work, and failures can cancel work that is still waiting.

I separated three responsibilities: 1) Execution determines the query's meaning
and produces initial data plus a finite description of remaining work; 2)
WorkQueue semantics describes legal histories of publications, announcements,
completions, and failures; 3) A concrete queue chooses its data structures and
event handling while satisfying those semantics.

This is useful because the client does not care whether the server uses a FIFO,
maps, promises, or some other mechanism. The client cares about the resulting
history: did the right pieces arrive, with valid IDs, without duplication or
loss?

Here, a history is the sequence of output events observed so far. An admitted
history is one the queue's output interface permits. The proposed
[WorkQueue conformance contract][queue-contract] has four conditions:

1. After initialization, the empty update history is admitted.
2. Every prefix of an admitted history is also admitted.
3. Every admitted history has a valid accounting explanation for the submitted
   work and its initial notices.
4. Finished histories are exactly admitted runs that account for all the work.

The third condition carries most of the substance. Published values must come
from the submitted work and be fresh. Dependencies and stream order must be
respected. Notices and closures must identify the right delivery groups.
Failures must justify the cancellations attributed to them. Finishing must
leave every task and delivery accounted for.

These rules constrain what the queue emits, not how it stores its bookkeeping.
The proof must show that every output can be explained by the accounting rules;
the running queue does not need to construct or store that explanation. Several
settlement orders and batching choices can still be legal.

<figure class="incremental-figure">
  <div class="incremental-panel incremental-architecture">
    <div class="incremental-kicker">Execution supplies work + initial response metadata</div>
    <div class="incremental-card incremental-card--blue">
      <h3>Client-visible response guarantees</h3>
      <p>Valid IDs · no overlapping data · reconstruction</p>
    </div>
    <div class="incremental-connector">↑ Proof of response correctness</div>
    <div class="incremental-card incremental-card--teal">
      <h3>Independent WorkQueue contract</h3>
      <p>Which output histories are legal?</p>
    </div>
    <div class="incremental-connector">↑ Proof of implementation conformance</div>
    <div class="incremental-card incremental-card--gold">
      <h3>Executable Lean queue + publisher</h3>
      <p>Concrete state transitions and response mapping</p>
    </div>
    <div class="incremental-source-link">↕ Source review + executable tests · not a language-equivalence proof</div>
    <div class="incremental-card incremental-card--muted">
      <h3>GraphQL.js JavaScript implementation</h3>
    </div>
  </div>
  <figcaption>The contract connects two machine-checked proofs. The connection to JavaScript is a separate source-review and testing step.</figcaption>
</figure>

This contract is a proposed addition to the specification.
Its usefulness comes from both directions of the proof: it is strong enough to
derive response correctness, and a concrete corrected implementation can
satisfy it.

## What every conforming WorkQueue guarantees

With the WorkQueue contract in place, we can prove [general query properties][theorem-guide]
for any conforming implementation.

For any observed prefix, including one that pauses or contains errors:

- Delivery IDs are unique.
- Each patch refers to an announced, still-open ID.
- Delivered response positions do not overlap.

These are safety properties: they apply to what the client has already seen,
even if nothing else ever arrives.

For a complete finite run:

- Every announced ID completes exactly once.
- The `hasNext` lifecycle is valid, ending with `false`.

A queue cannot announce some work, forget it, and declare the response finished.

For a complete run with no counted errors:

- Every scalar or null leaf in the ordinary response is delivered exactly once.
- Merging the actual responses reconstructs ordinary GraphQL execution with
  `@defer` and `@stream` erased.

The distinction matters. A correct queue does not make an arbitrary resolver
terminate. Nor should a failed query be required to reconstruct the successful
response. The proof states each promise under the conditions that support it.

The model covers finite queries, inline-fragment defer and stream behavior,
pure fixed resolver outcomes, prepared inputs, response data, error counts, and
wire events. It does not cover arbitrary resolver side effects, infinite
streams, or whether the host eventually settles every task.

## Proving the GraphQL.js WorkQueue model

The general theorem gives us a target. The next job is to prove that a concrete
implementation satisfies it.

I modeled GraphQL.js's queue and publisher as an [executable state machine][queue-model]
in Lean. The underlying host events supply successes, failures, stream items, and
exhaustion.
The queue updates its task and group bookkeeping. The publisher prepares deliveries,
and the response mapper produces the `pending`, `incremental`, `completed`, and
`hasNext` entries the client sees.

I treated the host event source as a black box with a few required behaviors.
This lets us prove the WorkQueue contract from a smaller set of assumptions
about host scheduling.

The [conformance statement][queue-conformance] is small enough to read:

```lean
def createWorkQueueForScheduleConforms : Prop :=
  ∀ work schedule,
    ExecutedWork work
    → work.size ≠ 0
    → schedule.ValidFor work
    → (createWorkQueueForSchedule work schedule).Conforms work
```

It says: for every nonempty work tree produced by execution, and every host
event schedule valid for that work, the executable queue satisfies the
WorkQueue contract. A machine-checked proof establishes the whole statement.

The host assumptions describe input behavior: settled values match the work,
task outcomes are not settled twice, producer dependencies are respected, stream
items stay ordered, and events settle eligible work. They do not assume that the
queue's output is correct. Output correctness is what we prove.

Queue conformance is only part of the story. The responses emitted by the queue,
publisher, and response mapper must also satisfy the query-level correctness guarantees.
The [implementation-correctness statement][implementation-correctness]
connects the implementation's actual outputs to the general query-level theorems.

Here's one example. With names and routine parameters abbreviated,
the resulting [reconstruction guarantee][reconstruction-statement] says:

```lean
queue.Conforms
  → CompleteRun queue query responses
  → responses.totalErrors = 0
  → ∃ response,
      merge responses = some response
      ∧ response.semanticEquivalent
          (executeOrdinary query.eraseIncrementalDirectives)
```

Whatever permitted settlement order is used, a complete, error-free run
delivers pieces that merge into the ordinary
response. That is a guarantee about the whole result, not just queue bookkeeping.

Getting there took seventeen days. It began as a side project, with slow
progress between other work. During the final week I focused more closely on
the remaining conformance obligations.

A Prove2Me-style conjecture graph helped organize that work. I borrowed the
idea from the dependency graph described in
[Anthropic's account of formalizing Fermat's Last Theorem][flt]. The graph
made the current state clearer: which statements were proved, which depended
on unfinished work, and which unproved claims could invalidate a large branch
of the plan.

That last use was especially valuable. We attacked high-risk conjectures first.
Finding a counterexample early is better than building a large collection
of leaf lemmas and discovering afterward that their intended parent statement
was false. The graph served as a way to test the proof plan as well as to track
progress.

<figure class="incremental-figure incremental-video">
  <video class="incremental-video--landscape" controls playsinline preload="none" poster="{{ '/assets/images/graphql-incremental-delivery-proof-landscape.png' | relative_url }}" aria-label="Seventeen days of WorkQueue proof development, landscape view">
    <source src="{{ '/assets/videos/graphql-incremental-delivery-proof-landscape.mp4' | relative_url }}" type="video/mp4">
    <p><a href="{{ '/assets/videos/graphql-incremental-delivery-proof-landscape.mp4' | relative_url }}">Watch the landscape proof progression video.</a></p>
  </video>
  <video class="incremental-video--square" controls playsinline preload="none" poster="{{ '/assets/images/graphql-incremental-delivery-proof-square.png' | relative_url }}" aria-label="Seventeen days of WorkQueue proof development, clustered view">
    <source src="{{ '/assets/videos/graphql-incremental-delivery-proof-square.mp4' | relative_url }}" type="video/mp4">
    <p><a href="{{ '/assets/videos/graphql-incremental-delivery-proof-square.mp4' | relative_url }}">Watch the clustered proof progression video.</a></p>
  </video>
  <figcaption>Seventeen days of proof growth. An earlier snapshot contains 3,023 named theorems and 8,580 dependency relations leading to the central conformance theorem. The animation follows recorded source chronology, not every attempt or the first successful check of each lemma. Radial distance indicates dependency depth, not difficulty.</figcaption>
</figure>

By the final commit, the incremental proof modules totaled 142,542 lines.
Of those, 106,866—three quarters—prove that the concrete queue and publisher
conform. Direct incremental execution proofs take 10,791 lines, compared with
6,796 for ordinary execution. Most of the expansion was not field execution;
it was proving the queue's accounting correct.

<figure class="incremental-figure">
  <div class="incremental-panel incremental-chart">
    <div class="incremental-kicker">Incremental proof modules · source lines, not elapsed effort</div>
    <div class="incremental-bar-label"><span>Total proof development</span><strong>142,542 lines</strong></div>
    <div class="incremental-bar-track" aria-hidden="true">
      <span class="incremental-fill--blue" style="width: 7.571%"></span><span class="incremental-fill--teal" style="width: 4.592%"></span><span class="incremental-fill--purple" style="width: 12.866%"></span><span class="incremental-fill--gold" style="width: 74.971%"></span>
    </div>
    <dl class="incremental-legend">
      <div><dt><i class="incremental-fill--blue"></i>Execution semantics</dt><dd>10,791 lines</dd></div>
      <div><dt><i class="incremental-fill--teal"></i>Queue semantics</dt><dd>6,545 lines</dd></div>
      <div><dt><i class="incremental-fill--purple"></i>Response correctness</dt><dd>18,340 lines</dd></div>
      <div><dt><i class="incremental-fill--gold"></i>Implementation conformance</dt><dd>106,866 lines · 75%</dd></div>
    </dl>
  </div>
  <figcaption>Current proof-file sizes include comments and blank lines. They cover a broader scope than ordinary execution, and are distinct from the earlier dependency graph shown in the video.</figcaption>
</figure>

The working loop was to propose conformance conditions, attempt a difficult
claim, isolate a counterexample, and decide what it revealed. Sometimes the
implementation model was wrong. Sometimes the contract excluded legitimate
implementation behavior. Sometimes a bug was found in the original GraphQL.js
source code. Each correction changed the plan and produced a targeted regression.

I reviewed those public definitions and the correspondence with the draft and
GraphQL.js. AI agents implemented definitions, constructed proofs, investigated
counterexamples, and repaired the proof structure. Lean's kernel checked the
resulting proof. The effort totaled about 100 accumulated agent-hours and
2.4 billion total tokens (including 10 million output tokens) using GPT-6 Astra;
the seventeen days were elapsed time, with varying human attention.

The proof process made me revisit both the specification and the implementation multiple
times. The hardest part of that iteration was lifecycle accounting.

## Why lifecycle accounting was difficult

Asynchronous code often uses “done” for several different events. Incremental
delivery needs at least three:

<figure class="incremental-figure">
  <div class="incremental-panel">
    <div class="incremental-cards">
      <div class="incremental-card incremental-card--blue">
        <span class="incremental-step">Computation</span>
        <h3>Settlement</h3>
        <p>The host supplies a task result or stream event.</p>
      </div>
      <div class="incremental-card incremental-card--teal">
        <span class="incremental-step">Data delivery</span>
        <h3>Publication</h3>
        <p>A successful value becomes part of an observable update.</p>
      </div>
      <div class="incremental-card incremental-card--gold">
        <span class="incremental-step">Protocol lifecycle</span>
        <h3>Completion</h3>
        <p>The client is told that an announced delivery ID is closed.</p>
      </div>
    </div>
    <div class="incremental-wait"><span>Nested value settles</span><span>→ Buffered, awaiting parent release →</span><span>Value publishes</span></div>
  </div>
  <figcaption>A value can be settled but not publishable. A group can publish data but remain open. These are distinct events, not synonyms for “done.”</figcaption>
</figure>

Nested delivery is a little like an onion: an inner deferred layer may need its
outer layer released before it can be delivered. But overlapping selections
and streams make the dependencies more tangled than simple nesting. Failures
add another complication: a group can fail before its ID has even been announced.

The proof encountered distinctions that are easy to lose in an informal queue
description. A failed group and a successfully retired group may both be absent
from an "active" map, but a child registered later must respond differently to
each.

These cases also changed the proposed contract. At first I put ownership rules
on raw queue output. GraphQL.js's publisher chooses the effective owner
later, so the rules needed to describe the published output. We then had to
distinguish two questions for a shared value: which surviving group keeps it
eligible for delivery, and which announced group's ID labels its patch? Those
groups need not be the same. Requiring one group to play both roles would
reject legitimate behavior.

The queue must account for computation, buffered values, release dependencies,
accepted failures, and client-visible notices together. **Settlement is not
publication, and publication is not completion.** That distinction explains the
most revealing bug found during the work.

## One of the bugs found in GraphQL.js

Consider this operation:

```graphql
{
  ... @defer(label: "R") { bad x }
  ... @defer(label: "P") {
    slow
    ... @defer(label: "C") { x }
  }
}
```

Here, `bad: String!` returns null, so R fails. The nullable field `x` returns
`"X"` successfully, and `slow` returns `"ok"`. All three resolvers start. Change
only their settlement order, and the audited GraphQL.js v17.0.1
[implementation][js-queue] produces different outcomes:

<figure class="incremental-figure">
  <div class="incremental-panel incremental-timelines">
    <div class="incremental-kicker">Same operation · same resolver results</div>
    <div class="incremental-run">
      <div class="incremental-run-title">Order A · value delivered</div>
      <div class="incremental-cards">
        <div class="incremental-card"><span class="incremental-step">1 · bad</span><p>R fails.</p></div>
        <div class="incremental-card"><span class="incremental-step">2 · slow = "ok"</span><p>P releases C.</p></div>
        <div class="incremental-card incremental-card--teal"><span class="incremental-step">3 · x = "X"</span><p>C publishes the successful value.</p></div>
      </div>
      <div class="incremental-outcome incremental-outcome--teal">Response includes x: "X".</div>
    </div>
    <div class="incremental-run">
      <div class="incremental-run-title">Order B · value lost</div>
      <div class="incremental-cards">
        <div class="incremental-card"><span class="incremental-step">1 · bad</span><p>R fails.</p></div>
        <div class="incremental-card incremental-card--red"><span class="incremental-step">2 · x = "X"</span><p>C waits for P, but is pruned as “empty.”</p></div>
        <div class="incremental-card"><span class="incremental-step">3 · slow = "ok"</span><p>P releases its children. C is already gone.</p></div>
      </div>
      <div class="incremental-outcome incremental-outcome--red">Response ends without x.</div>
    </div>
    <div class="incremental-result">Corrected behavior of order B: retain C's buffered value → P releases C → drain C and publish x.</div>
  </div>
  <figcaption>The audited queue loses a successful value in one permitted settlement order. The correction retains buffered work and publishes it when its parent releases it.</figcaption>
</figure>

Same operation. Same resolver results. Order A delivers `x`; in order B, the
successfully computed field disappears.

In order B, `x` settles before `slow`, leaving C with no unfinished task. Its value is
still buffered, waiting for P to release C. The old pruning rule treats C as
empty and removes it. When P eventually releases its children, the successful
value has already been lost.

The correction has two parts: retain unpublished memberships, and drain settled
groups when their parent releases them. Retention alone can leave the value
stalled; draining alone has nothing to publish if the group has already been
pruned.

The broader audit found five issues:

- A completion could be emitted before its ID was announced.
- A successful shared value could be lost while waiting for its parent (shown earlier).
- Children registered after a parent's failure could escape cancellation.
- Previously collected errors could disappear when a later field failed.
- An explicit `label: null` raised a question about whether null should appear
  on the wire. This is not a confirmed bug. I posted
  a [clarification question][null-question] on the draft spec PR.

Two GraphQL.js pull requests carry the corrections:
[retain deferred outcomes until group release][queue-pr] and
[preserve collected errors on incremental failure][errors-pr].
The Lean model proves the corrected algorithm; those
changes have not yet been merged into GraphQL.js as of this writing.

## Incremental delivery now has a formal model

We now have a formalization of incremental delivery, an independent
WorkQueue contract, and proofs of the general correctness guarantees shared by all
conforming queues. We also have a corrected executable model of GraphQL.js's
queue and publisher, proved to conform to that contract, with its actual
outputs connected to the general theorems.

Beyond the GraphQL.js fixes, the specification work produced
[three reported draft corrections][spec-corrections]
about aliased response paths, the final `hasNext` value, and shared ID-allocation
state. The larger WorkQueue contract is a potential contribution to the spec.

GraphQL's specification authors, incremental-delivery workgroup, and GraphQL.js
maintainers supplied the design this project formalizes. This formalization work
contributes a precise account of its queue contract, general correctness results,
and concrete counterexamples along with their fixes.

I expected to verify a small execution extension and ended up formalizing a
concurrent response protocol. At the end of the day, the result gives us both an
executable reference and a reusable contract for other implementations to target.

(The [code and theorem guide][theorem-guide], [WorkQueue semantics][semantics-guide],
and [implementation proof map][implementation-guide] are available in
[graphql-lean][project].)

[v17]: https://graphql.org/blog/2026-06-15-introducing-graphql-js-v17/
[lean]: https://lean-lang.org/
[project]: https://github.com/duckki/graphql-lean
[snapshot]: https://github.com/duckki/graphql-lean/commit/c64eecf35458801dade61a1c9c7c46afc0419a3c
[execution]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/GraphQL/IncrementalDelivery/Execution.lean
[spec-pr]: https://github.com/graphql/graphql-spec/pull/1110
[spec-execution]: https://github.com/graphql/graphql-spec/blob/045e19363c2b55f127960bd3b5e8072a15b29aec/spec/Section%206%20--%20Execution.md
[queue-contract]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/GraphQL/IncrementalDelivery/WorkQueueSemantics.lean#L714-L750
[queue-model]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/GraphQL/IncrementalDelivery/WorkQueueImplementation.lean
[js-queue]: https://github.com/graphql/graphql-js/blob/961747301cf70e59aead2d7a5121779a79a52877/src/execution/incremental/WorkQueue.ts
[queue-conformance]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/GraphQL/IncrementalDelivery/WorkQueueImplementation.lean#L1098-L1109
[implementation-correctness]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/GraphQL/IncrementalDelivery/WorkQueueImplementation.lean#L1153-L1173
[reconstruction-statement]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/GraphQL/IncrementalDelivery/Correctness.lean#L624-L643
[theorem-guide]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/docs/incremental-delivery/README.md#public-statements
[semantics-guide]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/docs/incremental-delivery/semantics.md
[implementation-guide]: https://github.com/duckki/graphql-lean/blob/c64eecf35458801dade61a1c9c7c46afc0419a3c/docs/incremental-delivery/implementation.md
[flt]: https://www.anthropic.com/news/formalizing-fermats-last-theorem
[queue-pr]: https://github.com/graphql/graphql-js/pull/4859
[errors-pr]: https://github.com/graphql/graphql-js/pull/4861
[spec-corrections]: https://github.com/graphql/graphql-spec/pull/1110#issuecomment-5745600794
[null-question]: https://github.com/graphql/graphql-spec/pull/1110#issuecomment-5750910092
