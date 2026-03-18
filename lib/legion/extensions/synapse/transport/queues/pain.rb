# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Transport
        module Queues
          if defined?(Legion::Transport::Queue)
            class Pain < Legion::Transport::Queue
              def queue_name
                'synapse.pain'
              end
            end
          end
        end
      end
    end
  end
end
