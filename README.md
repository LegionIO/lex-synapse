# lex-synapse

Cognitive routing layer for [LegionIO](https://github.com/LegionIO/LegionIO) task chains. Wraps task relationships with observation, learning, confidence scoring, pain signals, and self-governance.

## Installation

```bash
gem install lex-synapse
```

Or add to your Gemfile:

```ruby
gem 'lex-synapse'
```

## Standalone Client

Use the synapse engine with an initialized Sequel database containing this gem's migrations and Legion's data connection setting enabled. The host supplies that setup in a running LegionIO deployment.

```ruby
require 'legion/extensions/synapse/client'

client = Legion::Extensions::Synapse::Client.new
synapse = client.create(source_function_id: 1, target_function_id: 2)
result = client.evaluate(synapse_id: synapse.id, payload: { message: 'hello' })
result[:success]     # => true
result[:mode]        # => :transform (permission tier, not proof of transformation)
result[:transformed] # => false (no transform configured)
result[:result]      # => { message: 'hello' }

report = client.report(synapse_id: synapse.id)
report[:confidence]              # => 0.72
report[:signals_24h]             # => 1
report[:completed_outcomes_24h]  # => 0
report[:success_rate]            # => nil (downstream completion is unknown)
```

For configured rules, require `legion/extensions/conditioner/client` and `legion/extensions/transformer/client`, then inject `conditioner_client:` and `transformer_client:` into `Client.new`. `Client#evaluate` uses those injected clients. A successful evaluation is separate from downstream task completion.

## Architecture

### Three-Layer Model

```
Layer 1 (Bones)  — Explicit relationships defined by users (lex-tasker)
Layer 2 (Nerves) — Synapses wrapping relationships with learning (lex-synapse)
Layer 3 (Mind)   — GAIA cognitive coordination + Apollo shared knowledge
```

### Confidence Scoring

Each synapse has a confidence score (0.0-1.0) that governs what it's allowed to do:

| Range | Mode | Permitted Actions |
|-------|------|-------------------|
| 0.0 <= confidence < 0.3 | OBSERVE | Log what it would do, pass through unchanged |
| 0.3 <= confidence < 0.6 | FILTER | Can suppress signals, cannot modify |
| 0.6 <= confidence < 0.8 | TRANSFORM | Can filter + transform within defined schemas |
| 0.8 <= confidence <= 1.0 | AUTONOMOUS | Generates proposals for self-modification |

**Starting scores**: explicit=0.7, emergent=0.3, seeded=0.5

Observe-mode pass-through and clean attention rejections are neutral: they neither change confidence nor advance/reset the success streak. Signals retain the conditioner verdict even when observe mode passes the payload through. A confirmed downstream success credits an observe evaluation once (+0.02 and its success-streak increment), so an observing synapse can recover; eligible evaluations already credited at evaluation time are never credited again.

**Adjustments**: eligible evaluation success +0.02, failure -0.05, validation failure -0.03, more than 50 consecutive successful evaluations +0.05 bonus (streak persisted; failures reset it)

**Decay**: Unused synapses fade at 0.998x per hour (~4.7% per day of inactivity; half-life ~14.4 days)

### Pain Signals

Downstream task failures propagate backward through the chain:
- Each failure reduces confidence by 0.05
- 3+ consecutive failures trigger auto-revert to last known-good state (calls `revert` directly)
- Extreme failure rates trigger dampening (homeostasis)

### Homeostasis

- **Spike detection**: Counts windows with throughput >3x baseline for 60+ seconds
- **Drought detection**: Counts windows with zero throughput for 10x the average interval
- **Baseline tracking**: Exponential moving average of signals/minute, bootstrapped from zero on the first traffic window; the homeostasis actor reports anomalies without changing status

## Runners

### Evaluate
Runner: `evaluate(synapse_id:, payload: {}, conditioner_client: nil, transformer_client: nil, **)`. Client: `evaluate(synapse_id:, payload: {})`.

Main signal flow: load synapse → check autonomy → run attention (conditioner) → run transform (transformer) → record signal → adjust confidence → generate proposals if AUTONOMOUS.

### Task-chain integration

The lex-synapse side is implemented here; live dispatch requires the lex-tasker companion tracked in [#18](https://github.com/LegionIO/lex-synapse/issues/18). With that companion and this extension loaded, relationships explicitly wrapped
as synapses are evaluated before child task creation. Unwrapped relationships retain
the ordinary conditioner/transformer pipeline. Suppressed or unavailable evaluations
do not dispatch a child; accepted evaluations pass their result directly to the target
without applying the relationship's rules a second time. Task payloads must be hashes.
Delayed children retain the evaluated payload and its signal correlation.

The LegionIO host's `task.failed` and `task.completed` events update the correlated
signal by task ID and target runner/function. Intermediate stage events and repeated
completion events do not count as additional outcomes. This integration uses the host
event bus for outcomes and synchronous evaluation at dispatch; it does not depend on
an AMQP producer publishing `synapse.evaluate` or `task.failed`.

### Pain
`handle_pain(synapse_id:, task_id: nil, signal_id: nil, **)`

Downstream failure handler. Task notifications must identify a correlated evaluation through `signal_id` or a unique `task_id`. Redelivery is neutral; uncorrelated task notifications return an error. Calls without either ID record a manual failure. Pending evaluations do not interrupt the completed-outcome failure streak. The outcome and confidence penalty commit together; three completed failures trigger reversion.

### Revert
`revert(synapse_id:, to_version: nil, mutation_id: nil, trigger: 'pain', **)`

Restores a mutation’s `before_state`. `to_version` identifies the mutation being undone, rather than a target live-state version; omit it to undo the current live version. New history sequence numbers always exceed every prior history version, even after rollback lowers the live version. Legacy duplicate versions return an ambiguity error without changing state; use the immutable `mutation_id` to select exactly one historical row. Specify only one selector. Reversion appends a history entry and preserves existing identifiers.

### Crystallize
`crystallize(signal_pairs: [], threshold: 20)`

Creates emergent synapses from supplied source/target pairs meeting the threshold. With no supplied pairs, no synapses are created.

### Mutate
`mutate(synapse_id:, mutation_type:, changes:, trigger:)`

Versioned self-modification. Records before/after state snapshots.

### Report
`report(synapse_id:, **)`

Aggregates stats: confidence, status, 24h signal count, success rate, last mutation.

### Dream
`dream_replay(synapse_id: nil, **)` returns mutation-history metadata and a timeline. `dream_simulate(synapse_id:, mutation_type:, changes:, **)` changes a copy of the routing state and estimates confidence by assuming one success. Neither executes historical payloads or empirically validates a proposed change; routing state is unchanged.

### Propose / Challenge
`propose_reactive(synapse:, payload:, signal_id:, attention_result:, transform_result:, transformer_client: nil)` generates proposals from evaluation evidence. `propose_proactive` analyzes stored signals. The client exposes `proposals(synapse_id:, status: nil)` and `review_proposal(proposal_id:, status:)` for review.

`challenge_proposal(proposal_id:, transformer_client: @transformer_client, **)` and `run_challenge_cycle(transformer_client: @transformer_client, **)` use the client's injected reviewer by default; runner defaults are nil. The cycle challenges pending/deferred proposals and automatically applies auto-accepted proposals. See required-review rules below. `apply_proposal(proposal_id:, **)` handles explicit approvals or auto-acceptance; `resolve_challenge_outcomes(proposal_id:)` scores observed challenger outcomes. Query methods are `pending_challenges`, `challenges(proposal_id:)`, and `challenger_stats`.

### GAIA, knowledge entries, and blast radius

`gaia_summary(**)` returns aggregate health; `gaia_reflection(**)` adds recent mutation information. `promote(synapse_id: nil, **)` returns candidate knowledge entries without publishing them. `retrieve_and_seed(knowledge_entries:, **)` consumes supplied knowledge entries without querying Apollo. Live Apollo integration is tracked in [#30](https://github.com/LegionIO/lex-synapse/issues/30).

`compute(**)` recomputes blast-radius tiers from the active routing graph. `blast_tier(synapse_id:)` returns a stored tier. The private `analyze_routing` proposal stub is not a blast-radius API.

## Relationship Wrapper

Wrap existing Layer 1 relationships as synapses (opt-in, zero breaking changes):

```ruby
relationship = { id: 42, trigger_function_id: 1, function_id: 2,
                 conditions: '{"all":[...]}', transformation: '{"template":"..."}' }
synapse = Legion::Extensions::Synapse::Helpers::RelationshipWrapper.wrap(relationship)
```

## Data Model

Five tables: `synapses` (core routing + confidence + status + blast_radius), `synapse_mutations` (versioned history), `synapse_signals` (per-signal outcomes), `synapse_proposals` (proposal lifecycle), `synapse_challenges` (per-challenge verdicts).

## Transport

- **Exchange**: `synapse` (inherits from `Legion::Transport::Exchanges::Task`)
- **Queues**: `synapse.evaluate`, `synapse.pain`
- **Routing keys**: `synapse.evaluate`, `task.failed`

## Dependencies

- `lex-conditioner` >= 0.3.0
- `lex-transformer` >= 0.3.0
- Ruby >= 3.4
- [LegionIO](https://github.com/LegionIO/LegionIO) framework (for AMQP actor mode)
- Standalone Client works without the framework (requires Sequel + database)

### Outcome reporting

`report(synapse_id:)` measures the last 24 hours by signal creation time. `success_rate` is successful downstream outcomes divided by completed outcomes (`success` plus `failed`), and is `nil` when none are complete. `completed_outcomes_24h`, `successful_outcomes_24h`, and `failed_outcomes_24h` expose that denominator. `unresolved_signals_24h` includes pending tasks and evaluations that never dispatch; these do not count as completed failures. `evaluation_successes_24h` counts successful evaluation/pass-through records and is not proof of downstream completion or transformation execution.

`Integration.attach_task` associates an evaluation signal with its downstream task and target runner/function. `Integration.record_outcome` and the installed host task event listeners finalize that same signal once; duplicate or conflicting completion notifications do not create another attempt. Live task-chain attachment depends on the lex-tasker companion tracked in [#18](https://github.com/LegionIO/lex-synapse/issues/18).

### Required proposal review

The challenge cycle automatically applies auto-accepted proposals. HIGH/CRITICAL blast radius or impact at/above the configured threshold requires a completed LLM review before automatic acceptance/application. Missing reviewers, errors, malformed responses, and abstentions leave the proposal pending with `challenge_state: deferred`; the cycle reports a `deferred` count. The scheduled actor constructs a transformer client and requests a JSON verdict; standalone clients use their injected reviewer. New proposals have priority over due retries. Incomplete or unavailable reviews use persisted exponential backoff (300 seconds initially, capped at 3600) and expire after three attempts. Configure `review_retry_seconds`, `review_max_retry_seconds`, and `review_max_attempts` under `lex-synapse.challenge`. Explicit operator approval can still reopen an expired proposal. Lower-impact proposals retain conflict-based automatic decisions. Explicit operator approval remains a separate application path.

### Idle decay timing

Only active synapses with at least one complete hour since their most recent signal are eligible for idle decay. The actor applies `0.998 ** elapsed_whole_hours`, measuring from the latest of creation time, last signal, and the persisted `last_decay_at` checkpoint. A recent signal resets the idle interval. Fractional hours remain for the next tick. A delayed tick or restart catches up the current idle interval; repeated ticks do not apply the same hours twice. Confidence is multiplied in SQL and the checkpoint advances in the same conditional update, without an explicit row lock. Changed checkpoints and newly arrived signals prevent stale ticks from writing. Existing rows receive the upgrade timestamp as their initial checkpoint so pre-upgrade idle hours are not charged twice.

## License

MIT

### Proposal and review settings

Configure `extensions.synapse.proposals` and `extensions.synapse.challenge` using symbol keys through `Legion::Settings` (JSON configuration keys are normalized by the loader). Defaults are exposed by `Legion::Extensions::Synapse.default_settings`. Standalone clients use the same settings and defaults. Migrate the former top-level `lex-synapse` section to `extensions.synapse`; that legacy path is no longer read.

Scheduled crystallization samples the latest 1000 completed child tasks from the shared `tasks` table and groups their parent/child function IDs. At least 20 sampled edges are required for an observing emergent synapse. Failed or pending children do not count. Existing function pairs are skipped on later cycles. Standalone callers may still supply `signal_pairs:` explicitly; an empty array disables collection for that call.

Transform proposals resolve numeric target function IDs through the shared function/runner/extension catalog to registered tool input schemas. If no rich schema is registered, recorded keyword signatures supply property names and required arguments without inventing types. Standalone databases without the host catalog use an empty target schema.
