# frozen_string_literal: true

require_relative '../runners/challenge'

module Legion
  module Extensions
    module Synapse
      module Actor
        class Challenge < Legion::Extensions::Actors::Every
          include Legion::Extensions::Synapse::Runners::Challenge

          def runner_class = self.class

          def runner_function
            'run_challenge_cycle'
          end

          def time
            60
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
        end
      end
    end
  end
end
