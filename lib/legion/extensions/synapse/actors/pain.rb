# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Actor
        class Pain < Legion::Extensions::Actors::Subscription
          def runner_function
            'handle_pain'
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
