# lex-synapse: Cognitive Routing Layer for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-core/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Cognitive routing layer that wraps task chain relationships with observation, learning, confidence scoring, pain signals, homeostasis, and self-governance. Sits between Layer 1 (explicit user-defined relationships in lex-tasker) and Layer 3 (GAIA cognitive coordination + Apollo shared knowledge).

**GitHub**: https://github.com/LegionIO/lex-synapse
**License**: MIT
**Version**: 0.1.0

## Architecture

```
Legion::Extensions::Synapse
├── Actors/
│   ├── Evaluate        # Subscription — main signal evaluation
│   ├── Pain            # Subscription — task.failed handler
│   ├── Crystallize     # Every 300s — emergent synapse detection
│   ├── Homeostasis     # Every 30s — spike/drought monitoring
│   └── Decay           # Every 3600s — idle confidence decay
├── Runners/
│   ├── Evaluate        # attention -> transform -> route -> record
│   ├── Pain            # failure recording, confidence hit, auto-revert
│   ├── Crystallize     # unrouted traffic analysis, emergent creation
│   ├── Mutate          # versioned self-modification with snapshots
│   ├── Revert          # rollback to previous mutation version
│   └── Report          # aggregate stats for GAIA consumption
├── Helpers/
│   ├── Confidence      # scoring, adjustments, autonomy ranges, decay
│   ├── Homeostasis     # spike/drought detection, baseline tracking
│   └── RelationshipWrapper  # Layer 1 -> Layer 2 wrapping
├── Data/
│   ├── Migrations/     # 001 synapses, 002 mutations, 003 signals
│   └── Models/         # Synapse, SynapseMutation, SynapseSignal
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

## Dependencies

| Gem | Purpose |
|-----|---------|
| `lex-conditioner` >= 0.3.0 | Attention evaluation (condition rules) |
| `lex-transformer` >= 0.2.0 | Payload transformation (template engines) |
| `legion-data` | Required — database persistence via Sequel |

## Testing

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

308 specs, 96%+ coverage. Uses in-memory SQLite for model/runner tests.

---

**Maintained By**: Matthew Iverson (@Esity)
