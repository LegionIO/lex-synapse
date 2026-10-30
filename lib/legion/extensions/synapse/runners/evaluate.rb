# frozen_string_literal: true

require_relative '../helpers/confidence'
require_relative '../helpers/proposals'
require_relative '../data/models/synapse'
require_relative '../data/models/synapse_mutation'
require_relative '../data/models/synapse_signal'
require_relative 'propose'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Evaluate
          include Propose

          def evaluate(synapse_id:, payload: {}, conditioner_client: nil, transformer_client: nil)
            Data::Model.define_synapse_model
            Data::Model.define_synapse_signal_model
            Data::Model.define_synapse_proposal_model
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse
            return { success: false, error: 'synapse not active' } unless Helpers::Confidence::EVALUABLE_STATUSES.include?(synapse.status)

            mode = Helpers::Confidence.autonomy_mode(synapse.confidence)
            start_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :millisecond)

            # Step 1: Attention check
            attention_result = check_attention(synapse, payload, mode, conditioner_client)
            # Unavailable execution is not evidence for confidence or proposal learning.
            if attention_result[:unavailable]
              return {
                success: mode == :observe, mode: mode, passed: attention_result[:passed],
                transformed: false, result: payload, error: attention_result[:error],
                latency_ms: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :millisecond) - start_time
              }
            end

            # Step 2: Transform (if attention passed and confidence allows)
            transform_result = if attention_result[:passed] && Helpers::Confidence.can_transform?(synapse.confidence)
                                 run_transform(synapse, payload, transformer_client)
                               else
                                 { success: attention_result[:passed], result: payload }
                               end

            elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :millisecond) - start_time
            if transform_result[:unavailable]
              return {
                success: false, mode: mode, passed: attention_result[:passed],
                transformed: false, result: payload, error: transform_result[:error], latency_ms: elapsed
              }
            end

            # Step 3: Record signal
            signal_record = record_signal(synapse, attention_result[:passed], transform_result[:success], elapsed)

            # Step 4: Adjust confidence (skip if run_transform already penalized for validation failure)
            new_confidence = synapse.confidence
            unless transform_result[:validation_failure]
              event = transform_result[:success] ? :success : :failure
              new_confidence = Helpers::Confidence.adjust(synapse.confidence, event)
              synapse.update(confidence: new_confidence)
            end

            # Step 5: Generate proposals if autonomous
            if Helpers::Confidence.can_self_modify?(new_confidence) && Helpers::Proposals.reactive?
              propose_reactive(
                synapse: synapse, payload: payload, signal_id: signal_record&.id,
                attention_result: attention_result, transform_result: transform_result,
                transformer_client: transformer_client
              )
            end

            {
              success:     transform_result[:success],
              mode:        mode,
              passed:      attention_result[:passed],
              transformed: transform_result[:transformed] == true,
              result:      transform_result[:result],
              latency_ms:  elapsed
            }
          end

          private

          def check_attention(synapse, payload, mode, conditioner_client)
            return { passed: true } if synapse.attention.nil? || synapse.attention.empty?
            return { passed: mode == :observe, unavailable: true, error: 'conditioner unavailable' } unless conditioner_client.respond_to?(:evaluate)

            result = conditioner_client.evaluate(conditions: Legion::JSON.load(synapse.attention), values: payload)
            passed = result[:valid]

            # In OBSERVE mode, always pass through regardless of result
            passed = true if mode == :observe

            { passed: passed }
          end

          def run_transform(synapse, payload, transformer_client)
            return { success: true, result: payload } if synapse.transform.nil? || synapse.transform.empty?
            return { success: false, result: payload, unavailable: true, error: 'transformer unavailable' } unless transformer_client.respond_to?(:transform)

            transform_def = Legion::JSON.load(synapse.transform)
            result = transformer_client.transform(
              transformation: transform_def[:template] || transform_def[:transformation],
              payload:        payload,
              engine:         transform_def[:engine]&.to_sym,
              schema:         transform_def[:schema]
            )

            if result[:success]
              { success: true, transformed: true, result: result[:result] }
            else
              new_conf = Helpers::Confidence.adjust(synapse.confidence, :validation_failure)
              synapse.update(confidence: new_conf)
              { success: false, result: payload, error: result[:errors], validation_failure: true }
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

          include Legion::Extensions::Helpers::Lex if defined?(Legion::Extensions::Helpers::Lex)
        end
      end
    end
  end
end
