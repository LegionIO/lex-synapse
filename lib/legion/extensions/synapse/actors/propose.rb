# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Actor
        class Propose < Legion::Extensions::Actors::Every
          def runner_function
            'propose_proactive'
          end

          def time
            300
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
