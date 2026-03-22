# frozen_string_literal: true

require_relative '../runners/crystallize'

module Legion
  module Extensions
    module Synapse
      module Actor
        class Crystallize < Legion::Extensions::Actors::Every
          include Legion::Extensions::Synapse::Runners::Crystallize

          def runner_class = self.class

          def runner_function
            'crystallize'
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
