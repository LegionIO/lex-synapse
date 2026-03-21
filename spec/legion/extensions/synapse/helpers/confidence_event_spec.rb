# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/helpers/confidence'

unless defined?(Legion::Events)
  module Legion
    module Events
      def self.emit(*); end
    end
  end
end

RSpec.describe Legion::Extensions::Synapse::Helpers::Confidence do
  describe 'synapse.confidence_update event emission' do
    before { allow(Legion::Events).to receive(:emit) }

    it 'emits synapse.confidence_update on adjustment' do
      described_class.adjust(0.5, :success)
      expect(Legion::Events).to have_received(:emit).with(
        'synapse.confidence_update',
        hash_including(:delta, :event, :new_confidence)
      )
    end

    it 'includes correct delta in event' do
      described_class.adjust(0.5, :failure)
      expect(Legion::Events).to have_received(:emit).with(
        'synapse.confidence_update',
        hash_including(delta: -0.05, event: :failure)
      )
    end
  end
end
