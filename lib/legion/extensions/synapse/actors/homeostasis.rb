# frozen_string_literal: true

require 'legion/extensions/synapse/data/models/synapse'
require 'legion/extensions/synapse/data/models/synapse_signal'

module Legion
  module Extensions
    module Synapse
      module Actor
        class Homeostasis < Legion::Extensions::Actors::Every
          def runner_class = self.class
          def time = 30
          def use_runner? = false
          def check_subtask? = false
          def generate_task? = false

          def action(**)
            return { status: :skipped, reason: :no_data } unless defined?(Legion::Data)

            Legion::Extensions::Synapse::Data::Model.define_synapse_model
            Legion::Extensions::Synapse::Data::Model.define_synapse_signal_model
            unless defined?(Legion::Extensions::Synapse::Data::Model::Synapse) &&
                   defined?(Legion::Extensions::Synapse::Data::Model::SynapseSignal)
              return { status: :skipped, reason: :no_data }
            end

            results = { spikes: 0, droughts: 0, updated: 0 }

            cutoff = Time.now - 60
            window_seconds = 60.0
            signal_model = Legion::Extensions::Synapse::Data::Model::SynapseSignal
            synapse_model = Legion::Extensions::Synapse::Data::Model::Synapse

            # Single query: count signals per synapse in the last 60s window
            signal_counts = signal_model.where { created_at > cutoff }
                                        .group_and_count(:synapse_id)
                                        .as_hash(:synapse_id, :count)

            # Include new zero baselines so the first traffic window can initialize the EWMA
            active_synapses = synapse_model.where(status: 'active')
                                           .all
            return results if active_synapses.empty?

            # Collect updates in memory, then apply in a single batch to avoid connection churn
            updates = []

            active_synapses.each do |synapse|
              baseline = synapse.baseline_throughput
              # Convert raw count in the window to signals/minute for apples-to-apples comparison
              current  = (signal_counts.fetch(synapse.id, 0).to_f / window_seconds) * 60.0

              if Helpers::Homeostasis.spike?(current, baseline, duration_seconds: window_seconds)
                results[:spikes] += 1
              elsif Helpers::Homeostasis.drought?(current, baseline, silent_seconds: window_seconds)
                results[:droughts] += 1
              end

              new_baseline = Helpers::Homeostasis.update_baseline(baseline, current)
              updates << { synapse_id: synapse.id, baseline_throughput: new_baseline }
              results[:updated] += 1
            end

            # Batch-update all baselines in a single transaction
            unless updates.empty?
              synapse_model.db.transaction do
                updates.each do |u|
                  synapse_model.where(id: u[:synapse_id]).update(baseline_throughput: u[:baseline_throughput])
                end
              end
            end

            results
          end
        end
      end
    end
  end
end
