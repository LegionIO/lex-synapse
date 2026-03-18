# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Actor
        class Decay < Legion::Extensions::Actors::Every
          def runner_function
            'apply_decay'
          end

          def time
            3600
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
