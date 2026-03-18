# frozen_string_literal: true

require_relative '../helpers/confidence'
require_relative '../data/models/synapse'
require_relative '../data/models/synapse_signal'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Evaluate
          def evaluate(synapse_id:, payload: {}, conditioner_client: nil, transformer_client: nil)
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse
            return { success: false, error: 'synapse not active' } unless Helpers::Confidence::EVALUABLE_STATUSES.include?(synapse.status)

            mode = Helpers::Confidence.autonomy_mode(synapse.confidence)
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

            # Step 1: Attention check
            attention_result = check_attention(synapse, payload, mode, conditioner_client)

            # Step 2: Transform (if attention passed and confidence allows)
            transform_result = if attention_result[:passed] && Helpers::Confidence.can_transform?(synapse.confidence)
                                 run_transform(synapse, payload, transformer_client)
                               else
                                 { success: attention_result[:passed], result: payload }
                               end

            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - start_time

            # Step 3: Record signal
            record_signal(synapse, attention_result[:passed], transform_result[:success], elapsed)

            # Step 4: Adjust confidence
            event = transform_result[:success] ? :success : :failure
            new_confidence = Helpers::Confidence.adjust(synapse.confidence, event)
            synapse.update(confidence: new_confidence)

            {
              success:     transform_result[:success],
              mode:        mode,
              passed:      attention_result[:passed],
              transformed: transform_result[:success],
              result:      transform_result[:result],
              latency_ms:  elapsed
            }
          end

          private

          def check_attention(synapse, payload, mode, conditioner_client)
            return { passed: true } if synapse.attention.nil? || synapse.attention.empty?

            passed = if conditioner_client
                       result = conditioner_client.evaluate(conditions: Legion::JSON.load(synapse.attention), values: payload)
                       result[:valid]
                     else
                       true
                     end

            # In OBSERVE mode, always pass through regardless of result
            passed = true if mode == :observe

            { passed: passed }
          end

          def run_transform(synapse, payload, transformer_client)
            return { success: true, result: payload } if synapse.transform.nil? || synapse.transform.empty?
            return { success: true, result: payload } unless transformer_client

            transform_def = Legion::JSON.load(synapse.transform)
            result = transformer_client.transform(
              transformation: transform_def[:template] || transform_def[:transformation],
              payload:        payload,
              engine:         transform_def[:engine]&.to_sym,
              schema:         transform_def[:schema]
            )

            if result[:success]
              { success: true, result: result[:result] }
            else
              new_conf = Helpers::Confidence.adjust(synapse.confidence, :validation_failure)
              synapse.update(confidence: new_conf)
              { success: false, result: payload, error: result[:errors] }
            end
          end

          def record_signal(synapse, passed_attention, transform_success, latency_ms)
            Data::Model::SynapseSignal.create(
              synapse_id:        synapse.id,
              passed_attention:  passed_attention,
              transform_success: transform_success,
              latency_ms:        latency_ms.to_i
            )
          end
        end
      end
    end
  end
end
