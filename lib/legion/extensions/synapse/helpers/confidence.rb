# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Helpers
        module Confidence
          VALID_STATUSES = %w[active observing dampened].freeze
          EVALUABLE_STATUSES = %w[active observing].freeze
          VALID_ORIGINS = %w[explicit emergent seeded].freeze
          VALID_OUTCOMES = %w[success failed].freeze

          STARTING_SCORES = { explicit: 0.7, emergent: 0.3, seeded: 0.5 }.freeze
          ADJUSTMENTS = {
            success:            0.02,
            failure:            -0.05,
            validation_failure: -0.03,
            consecutive_bonus:  0.05
          }.freeze
          DECAY_RATE = 0.998
          CONSECUTIVE_BONUS_THRESHOLD = 50

          AUTONOMY_RANGES = {
            observe:    0.0..0.3,
            filter:     0.3..0.6,
            transform:  0.6..0.8,
            autonomous: 0.8..1.0
          }.freeze

          class << self
            def starting_score(origin)
              STARTING_SCORES.fetch(origin.to_sym, 0.5)
            end

            def adjust(confidence, event, consecutive_successes: 0)
              delta = ADJUSTMENTS.fetch(event, 0)
              result = confidence + delta
              result += ADJUSTMENTS[:consecutive_bonus] if event == :success && consecutive_successes > CONSECUTIVE_BONUS_THRESHOLD
              new_confidence = clamp(result)
              Legion::Events.emit('synapse.confidence_update', delta: delta, event: event, new_confidence: new_confidence) if defined?(Legion::Events)
              new_confidence
            end

            def decay(confidence, hours: 1)
              clamp(confidence * (DECAY_RATE**hours))
            end

            def autonomy_mode(confidence)
              AUTONOMY_RANGES.each do |mode, range|
                return mode if range.include?(confidence)
              end
              :observe
            end

            def can_filter?(confidence)
              confidence >= 0.3
            end

            def can_transform?(confidence)
              confidence >= 0.6
            end

            def can_self_modify?(confidence)
              confidence >= 0.8
            end

            private

            def clamp(value)
              value.clamp(0.0, 1.0)
            end
          end
        end
      end
    end
  end
end
