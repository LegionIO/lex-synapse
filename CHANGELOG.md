# Changelog

## [0.4.4] - 2026-03-22

### Changed
- Add sub-gem runtime dependencies: legion-cache, legion-crypt, legion-data, legion-json, legion-logging, legion-settings, legion-transport
- Replace hand-rolled stubs in spec_helper with real sub-gem requires (legion/logging, legion/json, legion/settings)
- Add Helpers::Lex and actor base class stubs to spec_helper for consistent test setup
- Fix Legion::JSON.dump calls in runners/promote.rb and specs to wrap kwargs in explicit hash (single positional arg)
- Force Legion::Settings.dig override in support/database.rb so lazy model definitions run against in-memory DB

## [0.4.3] - 2026-03-22

### Fixed
- Race condition in lazy model definition: concurrent threads could both pass `const_defined?` before either called `const_set`, producing "already initialized constant" warnings. Added shared mutex to all 5 `define_*_model` methods.

## [0.4.2] - 2026-03-22

### Fixed
- Add `include Helpers::Lex` to Crystallize, Challenge, Evaluate, Pain, and Propose runners so methods are callable at module level by framework actor auto-dispatch

## [0.4.1] - 2026-03-22

### Fixed
- Challenge, Propose, and Crystallize actors now include their runner modules and override `runner_class` to return `self.class`, fixing `NoMethodError` at runtime
- Decay actor converted to self-contained pattern (like Homeostasis) — no `Runners::Decay` module existed

## [0.4.0] - 2026-03-22

### Added
- Adversarial challenge phase for proposals: conflict detection, LLM challenge, weighted aggregation
- `synapse_challenges` table (migration 005) for per-challenge verdict tracking
- `Runners::Challenge` with challenge_proposal, resolve_challenge_outcomes, run_challenge_cycle
- `Helpers::Challenge` with settings, constants, impact threshold helpers
- `Actors::Challenge` polling every 60s for pending proposals
- Challenger confidence tracking with outcome-based learning loop
- Auto-accept/auto-reject thresholds for unanimous verdicts
- Client methods: challenge_proposal, challenges, challenger_stats
- New proposal statuses: auto_accepted, auto_rejected
- Impact scoring gates LLM challenge (expensive calls only for high-impact proposals)

## [0.3.2] - 2026-03-21

### Fixed
- Homeostasis actor converted to self-contained pattern — was referencing non-existent `Runners::Homeostasis` and `check_homeostasis` method, now implements `action` directly using `Helpers::Homeostasis` spike/drought checks

## [0.3.1] - 2026-03-20

### Added
- Emit `synapse.confidence_update` event on confidence adjustment for safety metrics

## [0.3.0] - 2026-03-19

### Added
- Autonomous observation mode: proposal engine for AUTONOMOUS tier (confidence 0.8+)
- `synapse_proposals` table with migration 004
- `Runners::Propose` with reactive proposals (no-template, transform failure, pain correlation)
- `Runners::Propose` with proactive analysis (success rate degradation, payload drift)
- `Actors::Propose` periodic actor for proactive analysis (every 300s)
- `Helpers::Proposals` settings helper with configurable thresholds
- Proposal hook in `Runners::Evaluate` for autonomous synapses (gated by settings)
- Client `proposals(synapse_id:, status:)` query method
- Client `review_proposal(proposal_id:, status:)` for approving/rejecting proposals
- LLM-backed proposal generation via lex-transformer LLM engine
- Proposal deduplication within configurable window
- Integration specs for full proposal workflow
- Settings: `lex-synapse.proposals.*` for master switch, reactive/proactive toggles, max_per_run, LLM engine options, thresholds

### Changed
- `lex-transformer` dependency bumped to >= 0.3.0 (requires LLM engine with engine_options)

## [0.2.3] - 2026-03-19

### Fixed
- Guard synapse model definition against missing table at require time; replace eager `class Synapse < Sequel::Model(:synapses)` with lazy `define_synapse_model` module method that checks `Legion::Data` connected and `table_exists?` before defining the constant — prevents `PG::UndefinedTable` error when gem loads before migrations run
- Apply same lazy-define guard to `SynapseMutation` and `SynapseSignal` models
- Add explicit `set_primary_key :id` and `key:` options on associations in anonymous Sequel model classes to prevent Sequel inferring `_id` column name for unnamed classes
- Call `define_synapse_model` (and related) at the top of each runner method and `RelationshipWrapper` class method before first model reference

## [0.2.2] - 2026-03-18

### Fixed
- Remove local path references from Gemfile (lex-conditioner, lex-transformer)

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
