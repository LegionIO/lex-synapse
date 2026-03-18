# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Transport
        extend Legion::Extensions::Transport if defined?(Legion::Extensions::Transport)

        def self.additional_e_to_q
          [
            { from: 'synapse', to: 'evaluate', routing_key: 'synapse.evaluate' },
            { from: 'task', to: 'pain', routing_key: 'task.failed' }
          ]
        end
      end
    end
  end
end
