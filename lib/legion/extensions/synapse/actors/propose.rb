# frozen_string_literal: true

require_relative '../runners/propose'

module Legion
  module Extensions
    module Synapse
      module Actor
        class Propose < Legion::Extensions::Actors::Every
          include Legion::Extensions::Synapse::Runners::Propose

          def runner_class = self.class

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
