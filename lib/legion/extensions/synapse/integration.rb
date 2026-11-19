# frozen_string_literal: true

require 'legion/logging/helper'
require 'legion/extensions/synapse/client'
require 'legion/extensions/conditioner/client'
require 'legion/extensions/transformer/client'

module Legion
  module Extensions
    module Synapse
      # Optional LegionIO/lex-tasker integration. Standalone clients need neither host.
      module Integration
        @event_mutex = Mutex.new

        class << self
          include Legion::Logging::Helper

          def evaluate_relationship(relationship_id:, payload:, **)
            Legion::Extensions::Synapse::Data::Model.define_synapse_model
            synapse = Legion::Extensions::Synapse::Data::Model::Synapse.first(relationship_id: relationship_id)
            return { wrapped: false } unless synapse

            client = Legion::Extensions::Synapse::Client.new(
              conditioner_client: Legion::Extensions::Conditioner::Client.new,
              transformer_client: Legion::Extensions::Transformer::Client.new
            )
            evaluation = client.evaluate(synapse_id: synapse.id, payload: payload)
            evaluation.merge(wrapped: true, allowed: evaluation[:success] == true && evaluation[:passed] == true)
          end

          def attach_task(signal_id:, task_id:, runner_class:, function:, **)
            return unless signal_id

            Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(id: signal_id).update(
              task_id: task_id, target_runner_class: runner_class.to_s, target_function: function.to_s
            )
          end

          def record_outcome(task_id:, outcome:, runner_class:, function:, **)
            raise ArgumentError, 'invalid task outcome' unless %i[success failed].include?(outcome)
            return { recorded: 0 } unless task_id

            Legion::Extensions::Synapse::Data::Model.define_synapse_signal_model
            # Data may be unavailable during host startup/shutdown; model definitions are lazy.
            return { recorded: 0 } unless Legion::Extensions::Synapse::Data::Model.const_defined?(:SynapseSignal, false)

            model = Legion::Extensions::Synapse::Data::Model::SynapseSignal
            recorded = 0
            model.db.transaction do
              model.where(task_id: task_id, downstream_outcome: nil,
                          target_runner_class: runner_class.to_s, target_function: function.to_s).all.each do |signal|
                if outcome == :failed
                  result = Legion::Extensions::Synapse::Client.new.handle_pain(
                    synapse_id: signal.synapse_id, task_id: task_id, signal_id: signal.id
                  )
                  recorded += 1 if result[:success] && !result[:duplicate]
                else
                  recorded += model.where(id: signal.id, downstream_outcome: nil).update(downstream_outcome: 'success')
                end
              end
            end
            { recorded: recorded }
          end

          def install_events!(events:, **)
            @event_mutex.synchronize do
              return if @event_bus.equal?(events)

              @event_bus = events
              events.on('task.failed') { |event| record_outcome(**event, outcome: :failed) }
              events.on('task.completed') { |event| record_outcome(**event, outcome: :success) }
            end
          end
        end
      end
    end
  end
end

# Events belongs to the optional LegionIO host, not the standalone extension dependencies.
Legion::Extensions::Synapse::Integration.install_events!(events: Legion::Events) if defined?(Legion::Events)
