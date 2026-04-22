# lex-synapse: Cognitive Routing Layer for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `../CLAUDE.md`
- **Grandparent**: `../../CLAUDE.md`

## Purpose

Cognitive routing layer that wraps task chain relationships with observation, learning, confidence scoring, pain signals, homeostasis, and self-governance. Sits between Layer 1 (explicit user-defined relationships in lex-tasker) and Layer 3 (GAIA cognitive coordination + Apollo shared knowledge).

**GitHub**: https://github.com/LegionIO/lex-synapse
**License**: MIT
**Version**: 0.4.11

## Architecture

```
Legion::Extensions::Synapse
├── Actors/
│   ├── Evaluate        # Subscription — main signal evaluation
│   ├── Pain            # Subscription — task.failed handler
│   ├── Crystallize     # Every 300s — emergent synapse detection
│   ├── Homeostasis     # Every 30s — spike/drought monitoring
│   ├── Decay           # Every 3600s — idle confidence decay
│   ├── Propose         # Every 300s — proactive proposal analysis for AUTONOMOUS synapses
│   └── Challenge       # Every 60s — adversarial challenge pipeline for pending proposals
├── Runners/
│   ├── Evaluate        # attention -> transform -> route -> record -> propose (if AUTONOMOUS)
│   ├── Pain            # failure recording, confidence hit, auto-revert (calls revert!), dampen
│   ├── Crystallize     # unrouted traffic analysis, emergent creation
│   ├── Mutate          # versioned self-modification with before/after snapshots
│   ├── Revert          # rollback to previous mutation version (restores before_state)
│   ├── Report          # aggregate stats for GAIA consumption
│   ├── Dream           # replay historical signals in simulation mode
│   ├── GaiaReport      # GAIA tick hook: report confidence and health per synapse
│   ├── Promote         # Apollo integration: promote high-confidence synapse patterns
│   ├── Retrieve        # Apollo integration: retrieve relevant synapse patterns
│   ├── Propose         # reactive (signal-driven) + proactive (periodic) proposal generation
│   └── Challenge       # conflict detection, LLM challenge, weighted aggregation, outcome resolution
├── Helpers/
│   ├── Confidence      # scoring, adjustments, autonomy ranges, decay
│   ├── Homeostasis     # spike/drought detection, baseline tracking
│   ├── RelationshipWrapper  # Layer 1 -> Layer 2 wrapping
│   └── Challenge       # settings, constants, impact threshold helpers
├── Data/
│   ├── Migrations/     # 001 synapses, 002 mutations, 003 signals, 004 proposals, 005 challenges, 006 slow_query_indexes, 007 blast_radius
│   └── Models/         # Synapse, SynapseMutation, SynapseSignal, SynapseProposal, SynapseChallenge
├── Transport/
│   ├── Exchanges/Synapse
│   ├── Queues/Evaluate, Pain
│   └── Messages/Signal, Pain
└── Client              # Standalone client including all runners
```

## Runner Methods (Public API)

| Runner | Method | Signature |
|---|---|---|
| Evaluate | `evaluate` | `evaluate(synapse_id:, payload: {}, conditioner_client: nil, transformer_client: nil)` |
| Pain | `handle_pain` | `handle_pain(synapse_id:, task_id: nil)` — records failure, adjusts confidence, calls `revert` on 3+ consecutive failures |
| Crystallize | `crystallize` | `crystallize(signal_pairs:, threshold: 20)` |
| Mutate | `mutate` | `mutate(synapse_id:, mutation_type:, changes:, trigger:)` |
| Revert | `revert` | `revert(synapse_id:, to_version: nil, trigger: 'pain')` — restores `before_state` from mutation record; records revert as new mutation |
| Report | `report` | `report(synapse_id:)` |
| Dream | `dream` | `dream(synapse_id:, limit:)` |
| GaiaReport | `gaia_report` | Called during GAIA tick cycle |
| Promote | `promote` | `promote(synapse_id:)` |
| Retrieve | `retrieve` | `retrieve(...)` |
| Propose | `propose`, `proposals`, `review_proposal` | `propose(synapse_id:, ...)` / `proposals(synapse_id:, status:)` / `review_proposal(proposal_id:, status:)` |
| Challenge | `challenge_proposal`, `challenges`, `challenger_stats` | `challenge_proposal(proposal_id:)` / `challenges(proposal_id:)` / `challenger_stats` |
| Blast Radius | `analyze_routing` | `analyze_routing(synapse_id:)` — logs blast radius analysis result |

## Key Thresholds

| Parameter | Value |
|-----------|-------|
| Explicit starting confidence | 0.7 |
| Emergent starting confidence | 0.3 |
| Seeded starting confidence | 0.5 |
| Success adjustment | +0.02 |
| Failure adjustment | -0.05 |
| Validation failure adjustment | -0.03 |
| Consecutive success bonus (>50) | +0.05 |
| Idle decay rate | *0.998/hour |
| Auto-revert threshold | 3 consecutive failures |
| Spike multiplier | 3x baseline for 60s |
| Drought threshold | 0 throughput for 10x avg interval |
| Crystallize threshold | 20 unrouted signals |

## Autonomy Ranges

| Confidence | Mode | Capabilities |
|------------|------|-------------|
| 0.0-0.3 | OBSERVE | Log, pass through unchanged |
| 0.3-0.6 | FILTER | Suppress signals |
| 0.6-0.8 | TRANSFORM | Filter + transform within schemas |
| 0.8-1.0 | AUTONOMOUS | Self-modify rules via proposals, infer transforms |

## Pain Auto-Revert

`Runners::Pain#handle_pain` calls `revert(synapse_id:, trigger: 'pain')` directly when `consecutive_failures >= 3`. The revert finds the latest mutation record for the synapse's current version, restores `before_state` (attention, transform, routing_strategy, confidence, status), decrements version, marks the mutation outcome as `'reverted'`, and creates a new mutation record with `outcome: 'reverted'`.

## Data Model

- **synapses**: Core routing definition with confidence, status, version, baseline_throughput, blast_radius
- **synapse_mutations**: Versioned change history with before/after JSON snapshots, trigger, outcome
- **synapse_signals**: Per-signal outcome records (attention pass, transform success, latency_ms, downstream outcome)
- **synapse_proposals**: Proposed changes with status lifecycle (pending → approved/rejected/applied/expired/auto_accepted/auto_rejected), challenge_state, challenge_score, impact_score
- **synapse_challenges**: Per-challenge verdicts (conflict/LLM), confidence tracking, outcome resolution

## Autonomous Observation Mode (v0.3.0)

AUTONOMOUS-tier synapses (confidence >= 0.8) generate proposals instead of executing autonomous actions. Proposals are reactive (triggered on signal evaluation in `Runners::Evaluate`) or proactive (generated periodically by `Actors::Propose`). Settings: `lex-synapse.proposals.*` (enabled, reactive, proactive, max_per_run, llm_engine_options, thresholds).

## Adversarial Challenge Phase (v0.4.0)

Pending proposals pass through: conflict detection → impact scoring → LLM challenge (gated by `impact_score >= 0.3`) → weighted aggregation → auto-accept/reject. Aggregation: `support_weight / (support_weight + challenge_weight)`, >= 0.85 auto-accepts, <= 0.15 auto-rejects. Settings: `lex-synapse.challenge.*`.

## GAIA / Apollo Integration (v0.2.2)

- **GaiaReport**: Called during GAIA tick to report per-synapse confidence and health metrics
- **Dream**: Replays historical signals in simulation without affecting live state
- **Promote**: Publishes high-confidence patterns to Apollo shared knowledge store
- **Retrieve**: Pulls relevant patterns from Apollo to seed new synapses or adjust confidence

## Dependencies

| Gem | Purpose |
|-----|---------|
| `lex-conditioner` >= 0.3.0 | Attention evaluation (condition rules) |
| `lex-transformer` >= 0.3.0 | Payload transformation (template engines) |
| `legion-cache` >= 1.3.11 | Cache access |
| `legion-crypt` >= 1.4.9 | Encryption/Vault |
| `legion-data` >= 1.4.17 | Required — database persistence via Sequel |
| `legion-json` >= 1.2.1 | JSON serialization |
| `legion-logging` >= 1.3.2 | Logging |
| `legion-settings` >= 1.3.14 | Settings |
| `legion-transport` >= 1.3.9 | AMQP |

## Testing

```bash
bundle install
bundle exec rspec     # 412 specs, 0 failures
bundle exec rubocop   # 0 offenses
```

Uses in-memory SQLite for model/runner tests.

---

**Maintained By**: Matthew Iverson (@Esity)
