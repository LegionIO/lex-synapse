# frozen_string_literal: true

require_relative '../helpers/confidence'
require_relative '../data/models/synapse'
require_relative '../data/models/synapse_signal'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Pain
          CONSECUTIVE_FAILURE_THRESHOLD = 3

          def handle_pain(synapse_id:, task_id: nil)
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            # Record failed signal
            Data::Model::SynapseSignal.create(
              synapse_id:         synapse.id,
              task_id:            task_id,
              passed_attention:   true,
              transform_success:  true,
              downstream_outcome: 'failed'
            )

            # Adjust confidence
            new_confidence = Helpers::Confidence.adjust(synapse.confidence, :failure)
            synapse.update(confidence: new_confidence)

            # Check consecutive failures
            consecutive = count_consecutive_failures(synapse)

            result = { success: true, confidence: new_confidence, consecutive_failures: consecutive }

            # Auto-revert on 3+ consecutive failures
            if consecutive >= CONSECUTIVE_FAILURE_THRESHOLD
              result[:action] = :auto_revert
              result[:reverted] = true
            end

            # Check if confidence dropped below autonomy threshold
            new_mode = Helpers::Confidence.autonomy_mode(new_confidence)
            result[:mode] = new_mode

            # Dampen if failure rate is extreme
            if should_dampen_from_pain?(synapse)
              synapse.update(status: 'dampened')
              result[:dampened] = true
            end

            result
          end

          private

          def count_consecutive_failures(synapse)
            recent = synapse.signals_dataset
                            .order(Sequel.desc(:id))
                            .limit(CONSECUTIVE_FAILURE_THRESHOLD)
                            .all
            recent.take_while { |s| s.downstream_outcome == 'failed' }.size
          end

          def should_dampen_from_pain?(synapse)
            window_start = Time.now - 300
            recent = synapse.signals_dataset
                            .where(downstream_outcome: 'failed')
                            .where { created_at >= window_start }
                            .count
            baseline_signals = [synapse.baseline_throughput * 5, 5].max
            recent > (baseline_signals * 2)
          end
        end
      end
    end
  end
end
