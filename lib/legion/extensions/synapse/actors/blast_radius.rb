# frozen_string_literal: true

require_relative '../runners/blast_radius'

module Legion
  module Extensions
    module Synapse
      module Actor
        class BlastRadius < Legion::Extensions::Actors::Every
          include Legion::Extensions::Synapse::Runners::BlastRadius

          def runner_class = self.class

          def runner_function
            'compute'
          end

          def time
            1800
          end

          def use_runner?
            false
          end

          def check_subtask?
            false
          end

          def generate_task?
            false
          end

          def action(**_opts)
            compute
          end
        end
      end
    end
  end
end
