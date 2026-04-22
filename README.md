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

Use the synapse engine without the full LegionIO framework:

```ruby
require 'legion/extensions/synapse/client'

# Optionally inject conditioner and transformer clients
conditioner = Legion::Extensions::Conditioner::Client.new
transformer = Legion::Extensions::Transformer::Client.new

client = Legion::Extensions::Synapse::Client.new(
  conditioner_client: conditioner,
  transformer_client: transformer
)

# Create a synapse
synapse = client.create(
  source_function_id: 1,
  target_function_id: 2,
  attention: '{"all":[{"fact":"status","operator":"equal","value":"open"}]}',
  transform: '{"template":"{\"message\":\"<%= title %>\"}","engine":"erb"}'
)

# Evaluate a signal through the synapse
result = client.evaluate(synapse_id: synapse.id, payload: { status: 'open', title: 'Bug fix' })
result[:success]     # => true
result[:mode]        # => :transform (based on confidence level)
result[:result]      # => { message: "Bug fix" }

# Get synapse stats
report = client.report(synapse_id: synapse.id)
report[:confidence]  # => 0.72
report[:signals_24h] # => 1
report[:success_rate] # => 1.0
```

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
| 0.0-0.3 | OBSERVE | Log what it would do, pass through unchanged |
| 0.3-0.6 | FILTER | Can suppress signals, cannot modify |
| 0.6-0.8 | TRANSFORM | Can filter + transform within defined schemas |
| 0.8-1.0 | AUTONOMOUS | Generates proposals for self-modification |

**Starting scores**: explicit=0.7, emergent=0.3, seeded=0.5

**Adjustments**: success +0.02, failure -0.05, validation failure -0.03, 50+ consecutive successes +0.05 bonus

**Decay**: Unused synapses fade at 0.998x per hour (~15% per day of inactivity)

### Pain Signals

Downstream task failures propagate backward through the chain:
- Each failure reduces confidence by 0.05
- 3+ consecutive failures trigger auto-revert to last known-good state (calls `revert` directly)
- Extreme failure rates trigger dampening (homeostasis)

### Homeostasis

- **Spike detection**: Throughput >3x baseline for 60+ seconds triggers dampening
- **Drought detection**: Zero throughput for 10x average interval flags for review
- **Baseline tracking**: Exponential moving average of signals/minute

## Runners

### Evaluate
`evaluate(synapse_id:, payload:, conditioner_client:, transformer_client:)`

Main signal flow: load synapse → check autonomy → run attention (conditioner) → run transform (transformer) → record signal → adjust confidence → generate proposals if AUTONOMOUS.

### Pain
`handle_pain(synapse_id:, task_id:)`

Downstream failure handler. Records failed signal, adjusts confidence, calls `revert` on 3+ consecutive failures, may dampen synapse.

### Revert
`revert(synapse_id:, to_version:, trigger:)`

Rolls back to a previous mutation version, restoring `before_state`. Records the revert as a new mutation entry.

### Crystallize
`crystallize(signal_pairs:, threshold: 20)`

Bottom-up emergence. Creates new synapses for source/target pairs exceeding the threshold.

### Mutate
`mutate(synapse_id:, mutation_type:, changes:, trigger:)`

Versioned self-modification. Records before/after state snapshots.

### Report
`report(synapse_id:)`

Aggregates stats: confidence, status, 24h signal count, success rate, last mutation.

### Dream
`dream(synapse_id:, limit:)`

Replays historical signals in simulation mode without affecting live state.

### Propose / Challenge
AUTONOMOUS-tier synapses generate proposals (reactive on evaluation, proactive periodically). Proposals are subjected to a multi-stage challenge pipeline: conflict detection → impact scoring → optional LLM challenge → weighted aggregation → auto-accept/reject.

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

## License

MIT
