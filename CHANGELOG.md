# Changelog

## [0.2.1] - 2026-03-18

### Changed
- Extract VALID_STATUSES, EVALUABLE_STATUSES, VALID_ORIGINS, VALID_OUTCOMES constants into Confidence module
- Replace inline status array in Evaluate#evaluate with EVALUABLE_STATUSES constant reference

## [0.2.0] - 2026-03-17

### Added
- `Runners::GaiaReport` with `gaia_summary` (tick-consumable stats) and `gaia_reflection` (mutation tally + summary for post-tick)
- `Runners::Dream` with `dream_replay` (read-only mutation timeline) and `dream_simulate` (what-if without modifying state)
- `Runners::Promote` pushes high-confidence synapse patterns to Apollo (threshold: confidence >= 0.9, no reverts in 24h)
- `Runners::Retrieve` seeds new synapses from Apollo knowledge entries (threshold: entry confidence >= 0.7)
- Client includes all 4 new runner modules
- 92 new specs (303 total), 96% coverage

## [0.1.0] - 2026-03-17

### Added
- Cognitive routing layer for LegionIO task chains
- Data model: `synapses`, `synapse_mutations`, `synapse_signals` tables with Sequel migrations
- Confidence scoring: starting scores by origin (explicit=0.7, emergent=0.3, seeded=0.5), event-based adjustments, idle decay, autonomy ranges (OBSERVE/FILTER/TRANSFORM/AUTONOMOUS)
- Homeostasis: spike detection (>3x baseline for 60s), drought detection (0 throughput for 10x avg interval), exponential moving average baseline tracking
- 6 core runners: evaluate (attention+transform+route+record), pain (failure handling, auto-revert), crystallize (emergent synapse creation), mutate (versioned self-modification), revert (rollback to previous version), report (aggregated stats)
- 5 actors: evaluate (subscription), pain (subscription), crystallize (every 5min), homeostasis (every 30s), decay (every 1hr)
- Transport layer: synapse exchange, evaluate/pain queues, signal/pain messages
- Standalone `Client` class with injected conditioner/transformer clients
- `RelationshipWrapper` helper for wrapping Layer 1 relationships as synapses
- 211 specs, 94%+ coverage
