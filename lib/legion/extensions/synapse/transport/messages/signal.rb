# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Transport
        module Messages
          if defined?(Legion::Transport::Message)
            class Signal < Legion::Transport::Message
              def routing_key
                'synapse.signal'
              end

              def exchange
                Legion::Transport::Exchanges::Task
              end
            end
          end
        end
      end
    end
  end
end
