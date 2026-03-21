# frozen_string_literal: true

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

          def action(**_opts)
            return { status: :skipped, reason: :no_data } unless defined?(Legion::Data)

            results = { spikes: 0, droughts: 0, updated: 0 }
            return results unless defined?(Legion::Extensions::Synapse::Data::Model::Synapse)

            Legion::Extensions::Synapse::Data::Model::Synapse
              .where(status: 'active')
              .where { baseline_throughput > 0 } # rubocop:disable Style/NumericPredicate
              .each do |synapse|
              baseline = synapse.baseline_throughput
              signals = synapse.signals_dataset.where { created_at > (Time.now - 60) }.count
              current = signals.to_f

              if Helpers::Homeostasis.spike?(current, baseline, duration_seconds: 60)
                results[:spikes] += 1
              elsif Helpers::Homeostasis.drought?(current, baseline, silent_seconds: 60)
                results[:droughts] += 1
              end

              new_baseline = Helpers::Homeostasis.update_baseline(baseline, current)
              synapse.update(baseline_throughput: new_baseline)
              results[:updated] += 1
            end

            results
          end
        end
      end
    end
  end
end
