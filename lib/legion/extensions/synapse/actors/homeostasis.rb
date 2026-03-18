# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Actor
        class Homeostasis < Legion::Extensions::Actors::Every
          def runner_function
            'check_homeostasis'
          end

          def time
            30
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
