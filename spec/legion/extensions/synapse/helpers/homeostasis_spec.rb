# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/helpers/homeostasis'

RSpec.describe Legion::Extensions::Synapse::Helpers::Homeostasis do
  describe '.spike?' do
    it 'returns true when throughput exceeds 3x baseline for >= 60 seconds' do
      expect(described_class.spike?(100, 30, duration_seconds: 60)).to be true
    end

    it 'returns true when throughput is well above threshold and duration met' do
      expect(described_class.spike?(1000, 10, duration_seconds: 120)).to be true
    end

    it 'returns false when throughput is exactly 3x baseline (not strictly greater)' do
      expect(described_class.spike?(90, 30, duration_seconds: 60)).to be false
    end

    it 'returns false when throughput is below 3x baseline' do
      expect(described_class.spike?(50, 30, duration_seconds: 60)).to be false
    end

    it 'returns false when duration is less than 60 seconds' do
      expect(described_class.spike?(100, 30, duration_seconds: 59)).to be false
    end

    it 'returns false when baseline is 0' do
      expect(described_class.spike?(100, 0, duration_seconds: 60)).to be false
    end

    it 'returns false when baseline is negative' do
      expect(described_class.spike?(100, -5, duration_seconds: 60)).to be false
    end

    it 'returns false when current throughput is 0' do
      expect(described_class.spike?(0, 30, duration_seconds: 60)).to be false
    end
  end

  describe '.drought?' do
    it 'returns true when throughput is 0 and silent for >= 10x average interval' do
      # baseline = 6/min, avg_interval = 10s, threshold = 100s
      expect(described_class.drought?(0, 6, silent_seconds: 100)).to be true
    end

    it 'returns true for exactly meeting the threshold' do
      # baseline = 60/min, avg_interval = 1s, threshold = 10s
      expect(described_class.drought?(0, 60, silent_seconds: 10)).to be true
    end

    it 'returns false when baseline is 0' do
      expect(described_class.drought?(0, 0, silent_seconds: 1000)).to be false
    end

    it 'returns false when baseline is negative' do
      expect(described_class.drought?(0, -1, silent_seconds: 1000)).to be false
    end

    it 'returns false when silent_seconds is below threshold' do
      # baseline = 6/min, avg_interval = 10s, threshold = 100s
      expect(described_class.drought?(0, 6, silent_seconds: 99)).to be false
    end

    it 'returns false when current throughput is non-zero' do
      expect(described_class.drought?(1, 6, silent_seconds: 1000)).to be false
    end
  end

  describe '.update_baseline' do
    it 'applies exponential moving average with default alpha 0.1' do
      result = described_class.update_baseline(100.0, 200.0)
      expect(result).to be_within(0.0001).of(110.0)
    end

    it 'applies EMA with custom alpha' do
      result = described_class.update_baseline(100.0, 200.0, alpha: 0.5)
      expect(result).to be_within(0.0001).of(150.0)
    end

    it 'returns current baseline when new sample equals baseline' do
      result = described_class.update_baseline(50.0, 50.0)
      expect(result).to be_within(0.0001).of(50.0)
    end

    it 'weights old baseline more heavily with low alpha' do
      result = described_class.update_baseline(100.0, 200.0, alpha: 0.01)
      expect(result).to be_within(0.0001).of(101.0)
    end

    it 'fully replaces baseline when alpha is 1.0' do
      result = described_class.update_baseline(100.0, 200.0, alpha: 1.0)
      expect(result).to be_within(0.0001).of(200.0)
    end
  end

  describe '.should_dampen?' do
    it 'returns true when spike conditions are met' do
      expect(described_class.should_dampen?(100, 30, duration_seconds: 60)).to be true
    end

    it 'returns false when spike conditions are not met' do
      expect(described_class.should_dampen?(50, 30, duration_seconds: 60)).to be false
    end

    it 'delegates to spike?' do
      expect(described_class).to receive(:spike?).with(100, 30, duration_seconds: 60).and_call_original
      described_class.should_dampen?(100, 30, duration_seconds: 60)
    end
  end

  describe '.should_flag_for_review?' do
    it 'returns true when drought conditions are met' do
      expect(described_class.should_flag_for_review?(0, 6, silent_seconds: 100)).to be true
    end

    it 'returns false when drought conditions are not met' do
      expect(described_class.should_flag_for_review?(0, 6, silent_seconds: 50)).to be false
    end

    it 'delegates to drought?' do
      expect(described_class).to receive(:drought?).with(0, 6, silent_seconds: 100).and_call_original
      described_class.should_flag_for_review?(0, 6, silent_seconds: 100)
    end
  end
end
