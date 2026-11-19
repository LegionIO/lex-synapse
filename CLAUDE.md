# lex-synapse: Cognitive Routing Layer for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `../CLAUDE.md`
- **Grandparent**: `../../CLAUDE.md`

## Purpose

Cognitive routing layer that wraps task chain relationships with observation, learning, confidence scoring, pain signals, homeostasis, and self-governance. Sits between Layer 1 (explicit user-defined relationships in lex-tasker) and Layer 3 (GAIA cognitive coordination + Apollo shared knowledge).

**GitHub**: https://github.com/LegionIO/lex-synapse
**License**: MIT
**Version**: see `lib/legion/extensions/synapse/version.rb`

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
│   ├── Dream           # mutation-history inspection and copied-state simulation
│   ├── GaiaReport      # aggregate confidence and health summaries for GAIA callers
│   ├── Promote         # prepare high-confidence synapse knowledge entries
│   ├── Retrieve        # seed synapses from caller-supplied knowledge entries
│   ├── Propose         # reactive (signal-driven) + proactive (periodic) proposal generation
│   └── Challenge       # conflict detection, LLM challenge, weighted aggregation, outcome resolution
├── Helpers/
│   ├── Confidence      # scoring, adjustments, autonomy ranges, decay
│   ├── Homeostasis     # spike/drought detection, baseline tracking
│   ├── RelationshipWrapper  # Layer 1 -> Layer 2 wrapping
│   └── Challenge       # settings, constants, impact threshold helpers
├── Data/
│   ├── Migrations/     # 001 synapses, 002 mutations, 003 signals, 004 proposals, 005 challenges, 006 slow_query_indexes, 007 blast_radius, 008 consecutive_successes, 009 task targets, 010 last_decay_at
│   └── Models/         # Synapse, SynapseMutation, SynapseSignal, SynapseProposal, SynapseChallenge
├── Transport/
│   ├── Exchanges/Synapse
│   ├── Queues/Evaluate, Pain
│   └── Messages/Signal, Pain
└── Client              # Standalone client including all runners
```

## Runner Methods (Public API)

The standalone `Client` includes these runners. `Client#evaluate(synapse_id:, payload: {})` injects the clients supplied at construction. The runner itself accepts `evaluate(synapse_id:, payload: {}, conditioner_client: nil, transformer_client: nil, **)`.

| Area | Callable signature | Behavior |
|---|---|---|
| Pain | `handle_pain(synapse_id:, task_id: nil, signal_id: nil, **)` | Correlates failure when a signal ID is supplied; otherwise inserts a legacy failure record |
| Crystallize | `crystallize(signal_pairs: [], threshold: 20)` | Creates emergent synapses from supplied pairs; the default empty input discovers nothing |
| Mutate | `mutate(synapse_id:, mutation_type:, changes:, trigger:)` | Writes routing state and mutation history transactionally |
| Revert | `revert(synapse_id:, to_version: nil, trigger: 'pain')` | Restores the selected mutation's before-state and records a new history entry |
| Report | `report(synapse_id:, **)` | Reports evaluation counts separately from completed downstream outcomes |
| Dream | `dream_replay(synapse_id: nil, **)` | Returns mutation-history metadata, not replayed payloads |
| Dream | `dream_simulate(synapse_id:, mutation_type:, changes:, **)` | Copies state and estimates confidence by assuming one success; does not run historical payloads or write routing state |
| GAIA | `gaia_summary(**)`, `gaia_reflection(**)` | Returns aggregate health and recent mutation summaries for a caller to consume |
| Promote | `promote(synapse_id: nil, **)` | Returns candidate knowledge entries; does not publish to Apollo |
| Retrieve | `retrieve_and_seed(knowledge_entries:, **)` | Seeds from caller-supplied knowledge; does not query Apollo |
| Propose | `propose_reactive(synapse:, payload:, signal_id:, attention_result:, transform_result:, transformer_client: nil)` | Generates proposals from supplied evaluation evidence |
| Propose | `propose_proactive` | Analyzes stored signals for eligible active synapses |
| Client review | `proposals(synapse_id:, status: nil)`, `review_proposal(proposal_id:, status:)` | Lists proposals or records an explicit review status |
| Challenge | `challenge_proposal(proposal_id:, transformer_client: @transformer_client, **)` | Client defaults to its injected reviewer; runner default is nil |
| Challenge | `run_challenge_cycle(transformer_client: @transformer_client, **)` | Client defaults to its injected reviewer; runner default is nil; challenges, applies auto-accepted proposals, then resolves outcomes |
| Challenge | `apply_proposal(proposal_id:, **)`, `resolve_challenge_outcomes(proposal_id:)` | Applies approved/auto-accepted proposals or resolves their challenger outcomes |
| Challenge queries | `pending_challenges`, `challenges(proposal_id:)`, `challenger_stats` | Returns pending/deferred work, review records, or resolved challenger statistics |
| Blast radius | `compute(**)`, `blast_tier(synapse_id:)` | Recomputes graph-derived blast tiers or returns one stored tier |

`analyze_routing` is a private proposal-analysis stub, not the blast-radius API. See the README for review prerequisites and integration limits.

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
| 0.0 <= confidence < 0.3 | OBSERVE | Log, pass through unchanged |
| 0.3 <= confidence < 0.6 | FILTER | Suppress signals |
| 0.6 <= confidence < 0.8 | TRANSFORM | Filter + transform within schemas |
| 0.8 <= confidence <= 1.0 | AUTONOMOUS | Self-modify rules via proposals, infer transforms |

## Pain Auto-Revert

`Runners::Pain#handle_pain` calls `revert(synapse_id:, trigger: 'pain')` directly when `consecutive_failures >= 3`. The revert finds the latest mutation record for the synapse's current version, restores `before_state` (attention, transform, routing_strategy, confidence, status), restores the saved live version, marks the mutation outcome as `'reverted'`, and creates a new uniquely versioned history record with `outcome: 'reverted'`.

## Data Model

- **synapses**: Core routing definition with confidence, status, version, baseline_throughput, blast_radius, consecutive_successes, last_decay_at
- **synapse_mutations**: Versioned change history with before/after JSON snapshots, trigger, outcome
- **synapse_signals**: Per-signal outcome records (observed attention verdict, evaluation success, latency_ms, correlated task/target, downstream outcome)
- **synapse_proposals**: Proposed changes with status lifecycle (pending → approved/rejected/applied/expired/auto_accepted/auto_rejected), challenge_state, challenge_score, impact_score
- **synapse_challenges**: Per-challenge verdicts (conflict/LLM), confidence tracking, outcome resolution

## Autonomous Proposal Application

AUTONOMOUS-tier synapses generate reactive or proactive proposals. `run_challenge_cycle` automatically applies auto-accepted proposals through the mutation runner; this is not observation-only operation. Explicitly approved proposals can be applied with `apply_proposal`. Settings: `lex-synapse.proposals.*`.

## Adversarial Challenge Phase

Impact scoring determines whether LLM review is required: impact >= the configured threshold (default 0.3) or HIGH/CRITICAL blast radius. Missing reviewers, errors, malformed responses, and abstentions leave a proposal pending with `challenge_state: deferred`. Deferred proposals remain retryable. After completed review, conflict detection and weighted aggregation determine the decision: support weight / total weight, >= 0.85 auto-accepts and <= 0.15 auto-rejects by default. Lower-impact proposals retain conflict-only decisions. The scheduled actor has no default reviewer and reports deferred counts; the standalone client uses its injected reviewer. Settings: `lex-synapse.challenge.*`.

## GAIA / Apollo Integration

- `gaia_summary` and `gaia_reflection` return health and mutation summaries for callers.
- `dream_replay` inspects mutation history. `dream_simulate` changes a copied state and assumes a success adjustment; neither executes historical payloads or proves routing quality.
- `promote` prepares knowledge entries, and `retrieve_and_seed` consumes supplied entries. Apollo network publication/retrieval remains tracked in [#30](https://github.com/LegionIO/lex-synapse/issues/30).
- Task-chain dispatch requires the lex-tasker companion tracked in [#18](https://github.com/LegionIO/lex-synapse/issues/18).

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
bundle exec rspec --format json --out tmp/rspec_results.json --format progress --out tmp/rspec_progress.txt
bundle exec rubocop -A
```

Uses in-memory SQLite for model/runner tests.

---

**Maintained By**: Matthew Iverson (@Esity)
