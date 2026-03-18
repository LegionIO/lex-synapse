# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Actor
        class Evaluate < Legion::Extensions::Actors::Subscription
          def runner_function
            'evaluate'
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
