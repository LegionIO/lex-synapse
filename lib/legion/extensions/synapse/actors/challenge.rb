# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Actor
        class Challenge < Legion::Extensions::Actors::Every
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
