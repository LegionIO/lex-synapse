# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative '../data/models/synapse_mutation'
require_relative '../data/models/synapse_signal'
require_relative '../helpers/confidence'

module Legion
  module Extensions
    module Synapse
      module Runners
        module GaiaReport
          def gaia_summary(**)
            Data::Model.define_synapse_model
            synapses = Data::Model::Synapse.all
            active = synapses.select { |s| s.status == 'active' }
            dampened = synapses.select { |s| s.status == 'dampened' }
            observing = synapses.select { |s| s.status == 'observing' }

            pain_threshold = 0.3
            elevated_pain = active.select { |s| s.confidence < pain_threshold }

            {
              success:             true,
              total_synapses:      synapses.size,
              active_count:        active.size,
              dampened_count:      dampened.size,
              observing_count:     observing.size,
              elevated_pain_count: elevated_pain.size,
              avg_confidence:      avg_confidence(active),
              emergent_candidates: observing.size,
              health_score:        compute_health_score(active, dampened, elevated_pain),
              blast_distribution:  blast_distribution(synapses)
            }
          end

          def gaia_reflection(**)
            Data::Model.define_synapse_mutation_model
            summary = gaia_summary
            recent_mutations = Data::Model::SynapseMutation
                               .where { created_at >= Time.now - 3600 }
                               .all

            {
              success:           true,
              summary:           summary,
              mutations_1h:      recent_mutations.size,
              mutation_types:    recent_mutations.map(&:mutation_type).tally,
              mutation_triggers: recent_mutations.map(&:trigger).tally
            }
          end

          private

          def avg_confidence(synapses)
            return 0.0 if synapses.empty?

            (synapses.sum(&:confidence) / synapses.size).round(4)
          end

          def compute_health_score(active, dampened, elevated_pain)
            return 1.0 if active.empty? && dampened.empty?

            total = active.size + dampened.size
            healthy = active.size - elevated_pain.size
            (healthy.to_f / total).round(4).clamp(0.0, 1.0)
          end

          def blast_distribution(synapses)
            tiers = %w[LOW MED HIGH CRITICAL]
            dist = tiers.to_h { |t| [t, 0] }
            dist['unknown'] = 0

            synapses.each do |s|
              tier = s.respond_to?(:blast_radius) && s.blast_radius ? s.blast_radius.upcase : 'unknown'
              if dist.key?(tier)
                dist[tier] += 1
              else
                dist['unknown'] += 1
              end
            end

            dist
          end
        end
      end
    end
  end
end
