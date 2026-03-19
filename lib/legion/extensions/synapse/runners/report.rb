# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative '../data/models/synapse_mutation'
require_relative '../data/models/synapse_signal'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Report
          def report(synapse_id:)
            Data::Model.define_synapse_model
            Data::Model.define_synapse_mutation_model
            Data::Model.define_synapse_signal_model
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            signals = synapse.signals_dataset
            window_start = Time.now - 86_400
            recent_signals = signals.where { created_at >= window_start }

            total_recent = recent_signals.count
            successful = recent_signals.where(downstream_outcome: 'success').count
            success_rate = total_recent.positive? ? (successful.to_f / total_recent).round(4) : 0.0

            last_mutation = synapse.mutations_dataset.order(Sequel.desc(:id)).first

            {
              success:       true,
              synapse_id:    synapse.id,
              confidence:    synapse.confidence,
              status:        synapse.status,
              origin:        synapse.origin,
              version:       synapse.version,
              signals_24h:   total_recent,
              success_rate:  success_rate,
              total_signals: signals.count,
              last_mutation: if last_mutation
                               {
                                 type:    last_mutation.mutation_type,
                                 trigger: last_mutation.trigger,
                                 version: last_mutation.version,
                                 outcome: last_mutation.outcome
                               }
                             end
            }
          end
        end
      end
    end
  end
end
