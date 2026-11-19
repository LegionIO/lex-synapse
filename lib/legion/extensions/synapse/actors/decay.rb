# frozen_string_literal: true

require 'legion/extensions/synapse/data/models/synapse'
require 'legion/extensions/synapse/data/models/synapse_signal'
require 'legion/extensions/synapse/helpers/confidence'

module Legion
  module Extensions
    module Synapse
      module Actor
        class Decay < Legion::Extensions::Actors::Every
          def runner_class = self.class
          def time = 3600
          def use_runner? = false
          def check_subtask? = false
          def generate_task? = false

          def action(now: Time.now, **)
            return { status: :skipped, reason: :no_data } unless defined?(Legion::Data)

            Legion::Extensions::Synapse::Data::Model.define_synapse_model
            Legion::Extensions::Synapse::Data::Model.define_synapse_signal_model
            unless defined?(Legion::Extensions::Synapse::Data::Model::Synapse) &&
                   defined?(Legion::Extensions::Synapse::Data::Model::SynapseSignal)
              return { status: :skipped, reason: :no_data }
            end

            model = Legion::Extensions::Synapse::Data::Model::Synapse
            decayed = 0
            model.where(status: 'active').select_map(:id).each do |synapse_id|
              model.db.transaction do
                synapse = model.where(id: synapse_id, status: 'active').for_update.first
                next unless synapse

                last_signal = Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse_id)
                                                                                     .order(Sequel.desc(:created_at)).first&.created_at
                idle_start = [synapse.created_at, last_signal, synapse.last_decay_at].compact.max
                hours = ((now - idle_start) / 3600).floor
                next unless hours.positive?

                confidence = Legion::Extensions::Synapse::Helpers::Confidence.decay(synapse.confidence, hours: hours)
                decayed += 1 if confidence != synapse.confidence
                synapse.update(confidence: confidence, last_decay_at: idle_start + (hours * 3600))
              end
            end

            { decayed: decayed }
          end
        end
      end
    end
  end
end
