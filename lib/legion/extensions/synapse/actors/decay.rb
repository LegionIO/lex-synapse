# frozen_string_literal: true

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

          def action(**_opts)
            return { status: :skipped, reason: :no_data } unless defined?(Legion::Data)

            Data::Model.define_synapse_model
            decayed = 0

            Data::Model::Synapse.where(status: 'active').each do |synapse|
              new_conf = Helpers::Confidence.decay(synapse.confidence, hours: 1)
              next if new_conf == synapse.confidence

              synapse.update(confidence: new_conf)
              decayed += 1
            end

            { decayed: decayed }
          end
        end
      end
    end
  end
end
