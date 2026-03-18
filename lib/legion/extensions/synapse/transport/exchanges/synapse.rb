# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Transport
        module Exchanges
          if defined?(Legion::Transport::Exchanges::Task)
            class Synapse < Legion::Transport::Exchanges::Task
            end
          end
        end
      end
    end
  end
end
