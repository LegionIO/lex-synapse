# lex-synapse: Cognitive Routing Layer for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-core/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Cognitive routing layer that wraps task chain relationships with observation, learning, confidence scoring, pain signals, homeostasis, and self-governance. Sits between Layer 1 (explicit user-defined relationships in lex-tasker) and Layer 3 (GAIA cognitive coordination + Apollo shared knowledge).

**GitHub**: https://github.com/LegionIO/lex-synapse
**License**: MIT
**Version**: 0.4.0

## Architecture

```
Legion::Extensions::Synapse
├── Actors/
│   ├── Evaluate        # Subscription — main signal evaluation
│   ├── Pain            # Subscription — task.failed handler
│   ├── Crystallize     # Every 300s — emergent synapse detection
│   ├── Homeostasis     # Every 30s — spike/drought monitoring
│   ├── Decay           # Every 3600s — idle confidence decay
│   ├── Propose          # Every 300s — proactive proposal analysis for AUTONOMOUS synapses
│   └── Challenge        # Every 60s — adversarial challenge pipeline for pending proposals
├── Runners/
│   ├── Evaluate        # attention -> transform -> route -> record
│   ├── Pain            # failure recording, confidence hit, auto-revert
│   ├── Crystallize     # unrouted traffic analysis, emergent creation
│   ├── Mutate          # versioned self-modification with snapshots
│   ├── Revert          # rollback to previous mutation version
│   ├── Report          # aggregate stats for GAIA consumption
│   ├── Dream           # replay historical signals in simulation mode; replay/simulate
│   ├── GaiaReport      # GAIA tick hook: report confidence and health per synapse
│   ├── Promote         # Apollo integration: promote high-confidence synapse patterns to shared knowledge
│   ├── Retrieve        # Apollo integration: retrieve relevant synapse patterns from shared knowledge
│   ├── Propose         # reactive (signal-driven) + proactive (periodic) proposal generation
│   └── Challenge       # conflict detection, LLM challenge, weighted aggregation, outcome resolution
├── Helpers/
│   ├── Confidence      # scoring, adjustments, autonomy ranges, decay
│   ├── Homeostasis     # spike/drought detection, baseline tracking
│   ├── RelationshipWrapper  # Layer 1 -> Layer 2 wrapping
│   └── Challenge       # settings, constants, impact threshold helpers
├── Data/
│   ├── Migrations/     # 001 synapses, 002 mutations, 003 signals, 004 proposals, 005 challenges
│   └── Models/         # Synapse, SynapseMutation, SynapseSignal, SynapseProposal, SynapseChallenge
├── Transport/
│   ├── Exchanges/Synapse
│   ├── Queues/Evaluate, Pain
│   └── Messages/Signal, Pain
└── Client              # Standalone client including all runners
```

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
| 0.8-1.0 | AUTONOMOUS | Self-modify rules, infer transforms |

## Data Model

- **synapses**: Core routing definition with confidence, status, version, baseline_throughput
- **synapse_mutations**: Versioned change history with before/after JSON snapshots
- **synapse_signals**: Per-signal outcome records (attention pass, transform success, latency, downstream outcome)
- **synapse_proposals**: Proposed changes with status lifecycle, challenge_state, challenge_score, impact_score
- **synapse_challenges**: Per-challenge verdicts (conflict/LLM), confidence tracking, outcome resolution

## Autonomous Observation Mode (v0.3.0)

- **Proposal engine**: AUTONOMOUS tier (confidence 0.8+) generates proposals instead of executing autonomous actions
- **Reactive proposals**: on signal evaluation — no-template inference, transform failure fix, attention pain correlation
- **Proactive proposals**: periodic analysis — success rate degradation, payload drift detection
- **LLM-backed**: proposals call lex-transformer LLM engine for real output generation
- **Settings**: `lex-synapse.proposals.*` — enabled, reactive, proactive, max_per_run, llm_engine_options, thresholds
- **Data**: `synapse_proposals` table with status lifecycle (pending -> approved/rejected/applied/expired)
- **Client methods**: `proposals(synapse_id:, status:)`, `review_proposal(proposal_id:, status:)`

## Adversarial Challenge Phase (v0.4.0)

- **Challenge pipeline**: pending proposals go through conflict detection (mechanical) -> impact scoring -> LLM challenge (gated) -> weighted aggregation -> auto-accept/reject/await-review
- **Conflict detection**: queries sibling pending proposals on same synapse; conflicting types produce 'challenge' verdict
- **LLM challenge**: gated by `impact_score >= 0.3`; calls lex-transformer LLM engine; parses SUPPORT/CHALLENGE/ABSTAIN
- **Aggregation**: `support_weight / (support_weight + challenge_weight)`, abstains excluded; >= 0.85 auto-accepts, <= 0.15 auto-rejects
- **Challenger confidence**: starting 0.5, correct +0.05, incorrect -0.08, decay *0.998/hr; tracks via outcome resolution after observation window (50 signals post-application)
- **Settings**: `lex-synapse.challenge.*` — enabled, impact_threshold, auto_accept_threshold, auto_reject_threshold, llm_engine_options, outcome_observation_window, max_per_cycle
- **Data**: `synapse_challenges` table; `synapse_proposals` gains challenge_state, challenge_score, impact_score columns
- **Statuses**: `auto_accepted`, `auto_rejected` added to proposal lifecycle
- **Client methods**: `challenge_proposal(proposal_id:)`, `challenges(proposal_id:)`, `challenger_stats`

## GAIA / Apollo Integration (v0.2.2)

- **GaiaReport runner**: Called during the GAIA tick cycle to report per-synapse confidence and health metrics.
- **Dream runner**: Replays historical signals in simulation mode. Used by the dream cycle to test routing hypothesis changes without affecting live state.
- **Promote runner**: Publishes high-confidence synapse patterns to the Apollo shared knowledge store when confidence exceeds threshold.
- **Retrieve runner**: Pulls relevant synapse patterns from Apollo to seed new synapses or adjust confidence for cold-start scenarios.

## Dependencies

| Gem | Purpose |
|-----|---------|
| `lex-conditioner` >= 0.3.0 | Attention evaluation (condition rules) |
| `lex-transformer` >= 0.3.0 | Payload transformation (template engines) |
| `legion-data` | Required — database persistence via Sequel |

## Testing

```bash
bundle install
bundle exec rspec     # 412 specs, 0 failures
bundle exec rubocop   # 0 offenses
```

412 specs, 94%+ coverage. Uses in-memory SQLite for model/runner tests.

---

**Maintained By**: Matthew Iverson (@Esity)
