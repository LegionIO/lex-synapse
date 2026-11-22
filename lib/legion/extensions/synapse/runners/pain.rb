# frozen_string_literal: true

require 'legion/extensions/synapse/helpers/confidence'
require 'legion/extensions/synapse/data/models/synapse'
require 'legion/extensions/synapse/data/models/synapse_signal'
require 'legion/extensions/synapse/runners/revert'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Pain
          include Legion::Extensions::Synapse::Runners::Revert

          CONSECUTIVE_FAILURE_THRESHOLD = 3

          def handle_pain(synapse_id:, task_id: nil, signal_id: nil, **)
            Data::Model.define_synapse_model
            Data::Model.define_synapse_signal_model
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            correlation = resolve_failure_signal(synapse: synapse, task_id: task_id, signal_id: signal_id)
            return correlation if correlation[:error]

            task_id = correlation[:task_id]
            signal_id = correlation[:signal_id]

            # Claim the outcome and its penalty together; revert runs after this transaction.
            new_confidence = record_failure(synapse: synapse, task_id: task_id, signal_id: signal_id)
            return { success: true, duplicate: true } unless new_confidence

            # Check consecutive failures
            consecutive = count_consecutive_failures(synapse)

            result = { success: true, confidence: new_confidence, consecutive_failures: consecutive }

            # Auto-revert on 3+ consecutive failures
            if consecutive >= CONSECUTIVE_FAILURE_THRESHOLD
              result[:action] = :auto_revert
              revert_result = revert(synapse_id: synapse_id, trigger: 'pain')
              result[:reverted] = revert_result[:success] == true
              if result[:reverted]
                synapse.refresh
                new_confidence = synapse.confidence
                result[:confidence] = new_confidence
              end
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

          def resolve_failure_signal(synapse:, task_id:, signal_id:)
            return {} unless task_id || signal_id

            dataset = synapse.signals_dataset
            signals = (signal_id ? dataset.where(id: signal_id) : dataset.where(task_id: task_id)).limit(2).all
            return { success: false, error: 'task requires one correlated evaluation signal' } unless signals.one?

            signal = signals.first
            return { success: false, error: 'signal belongs to a different task' } if task_id && signal.task_id != task_id

            { task_id: signal.task_id, signal_id: signal.id }
          end

          def record_failure(synapse:, task_id:, signal_id:)
            synapse.db.transaction do
              if signal_id
                changed = Legion::Extensions::Synapse::Data::Model::SynapseSignal
                          .where(id: signal_id, synapse_id: synapse.id, task_id: task_id, downstream_outcome: nil)
                          .update(downstream_outcome: 'failed', success_credit_pending: false)
                next if changed.zero?
              else
                Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
                  synapse_id: synapse.id, passed_attention: true, transform_success: true, downstream_outcome: 'failed'
                )
              end
              Legion::Extensions::Synapse::Helpers::Confidence.adjust_persisted(synapse: synapse, event: :failure)
            end
          end

          def count_consecutive_failures(synapse)
            recent = synapse.signals_dataset
                            .exclude(downstream_outcome: nil)
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

          include Legion::Extensions::Helpers::Lex if defined?(Legion::Extensions::Helpers::Lex)
        end
      end
    end
  end
end
