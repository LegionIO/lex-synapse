# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/helpers/confidence'

RSpec.describe Legion::Extensions::Synapse::Helpers::Confidence do
  describe 'VALID_STATUSES' do
    it 'includes active, observing, and dampened' do
      expect(described_class::VALID_STATUSES).to contain_exactly('active', 'observing', 'dampened')
    end
  end

  describe 'EVALUABLE_STATUSES' do
    it 'is a subset of VALID_STATUSES' do
      expect(described_class::EVALUABLE_STATUSES - described_class::VALID_STATUSES).to be_empty
    end

    it 'excludes dampened' do
      expect(described_class::EVALUABLE_STATUSES).not_to include('dampened')
    end
  end

  describe 'VALID_ORIGINS' do
    it 'matches STARTING_SCORES keys' do
      expect(described_class::VALID_ORIGINS.map(&:to_sym)).to contain_exactly(*described_class::STARTING_SCORES.keys)
    end
  end

  describe 'VALID_OUTCOMES' do
    it 'includes success and failed' do
      expect(described_class::VALID_OUTCOMES).to contain_exactly('success', 'failed')
    end
  end

  describe '.starting_score' do
    it 'returns 0.7 for explicit origin' do
      expect(described_class.starting_score(:explicit)).to eq(0.7)
    end

    it 'returns 0.3 for emergent origin' do
      expect(described_class.starting_score(:emergent)).to eq(0.3)
    end

    it 'returns 0.5 for seeded origin' do
      expect(described_class.starting_score(:seeded)).to eq(0.5)
    end

    it 'returns 0.5 for unknown origin' do
      expect(described_class.starting_score(:unknown)).to eq(0.5)
    end

    it 'accepts string origin and converts to symbol' do
      expect(described_class.starting_score('explicit')).to eq(0.7)
    end
  end

  describe '.adjust' do
    it 'increases confidence by 0.02 on success' do
      expect(described_class.adjust(0.5, :success)).to be_within(0.0001).of(0.52)
    end

    it 'decreases confidence by 0.05 on failure' do
      expect(described_class.adjust(0.5, :failure)).to be_within(0.0001).of(0.45)
    end

    it 'decreases confidence by 0.03 on validation_failure' do
      expect(described_class.adjust(0.5, :validation_failure)).to be_within(0.0001).of(0.47)
    end

    it 'applies consecutive bonus of 0.05 when consecutive_successes > 50' do
      result = described_class.adjust(0.5, :success, consecutive_successes: 51)
      expect(result).to be_within(0.0001).of(0.57)
    end

    it 'does not apply consecutive bonus when consecutive_successes == 50' do
      result = described_class.adjust(0.5, :success, consecutive_successes: 50)
      expect(result).to be_within(0.0001).of(0.52)
    end

    it 'does not apply consecutive bonus for non-success events' do
      result = described_class.adjust(0.5, :failure, consecutive_successes: 100)
      expect(result).to be_within(0.0001).of(0.45)
    end

    it 'clamps result at 0.0 when confidence would go negative' do
      expect(described_class.adjust(0.02, :failure)).to eq(0.0)
    end

    it 'clamps result at 1.0 when confidence would exceed max' do
      expect(described_class.adjust(0.99, :success)).to eq(1.0)
    end

    it 'returns 0.0 for unknown event' do
      expect(described_class.adjust(0.5, :unknown_event)).to be_within(0.0001).of(0.5)
    end
  end

  describe '.decay' do
    it 'reduces confidence by DECAY_RATE after 1 hour' do
      expect(described_class.decay(1.0, hours: 1)).to be_within(0.0001).of(0.998)
    end

    it 'reduces confidence over multiple hours' do
      expect(described_class.decay(1.0, hours: 10)).to be_within(0.0001).of(0.998**10)
    end

    it 'decays from a non-1.0 starting confidence' do
      expect(described_class.decay(0.5, hours: 1)).to be_within(0.0001).of(0.5 * 0.998)
    end

    it 'defaults to 1 hour of decay' do
      expect(described_class.decay(0.8)).to be_within(0.0001).of(0.8 * 0.998)
    end

    it 'clamps result at 0.0 for very low confidence over many hours' do
      expect(described_class.decay(0.0, hours: 1000)).to eq(0.0)
    end
  end

  describe '.autonomy_mode' do
    it 'returns :observe for confidence 0.0' do
      expect(described_class.autonomy_mode(0.0)).to eq(:observe)
    end

    it 'returns :observe for confidence 0.15 (within observe range)' do
      expect(described_class.autonomy_mode(0.15)).to eq(:observe)
    end

    it 'returns :observe for confidence 0.3 (observe range upper bound, inclusive)' do
      expect(described_class.autonomy_mode(0.3)).to eq(:observe)
    end

    it 'returns :filter for confidence 0.31 (above observe range)' do
      expect(described_class.autonomy_mode(0.31)).to eq(:filter)
    end

    it 'returns :filter for confidence 0.5 (within filter range)' do
      expect(described_class.autonomy_mode(0.5)).to eq(:filter)
    end

    it 'returns :filter for confidence 0.6 (filter range upper bound, inclusive)' do
      expect(described_class.autonomy_mode(0.6)).to eq(:filter)
    end

    it 'returns :transform for confidence 0.61 (above filter range)' do
      expect(described_class.autonomy_mode(0.61)).to eq(:transform)
    end

    it 'returns :transform for confidence 0.7 (within transform range)' do
      expect(described_class.autonomy_mode(0.7)).to eq(:transform)
    end

    it 'returns :transform for confidence 0.8 (transform range upper bound, inclusive)' do
      expect(described_class.autonomy_mode(0.8)).to eq(:transform)
    end

    it 'returns :autonomous for confidence 0.81 (above transform range)' do
      expect(described_class.autonomy_mode(0.81)).to eq(:autonomous)
    end

    it 'returns :autonomous for confidence 1.0 (max)' do
      expect(described_class.autonomy_mode(1.0)).to eq(:autonomous)
    end
  end

  describe '.can_filter?' do
    it 'returns true when confidence is exactly 0.3' do
      expect(described_class.can_filter?(0.3)).to be true
    end

    it 'returns true when confidence is above 0.3' do
      expect(described_class.can_filter?(0.5)).to be true
    end

    it 'returns false when confidence is below 0.3' do
      expect(described_class.can_filter?(0.29)).to be false
    end
  end

  describe '.can_transform?' do
    it 'returns true when confidence is exactly 0.6' do
      expect(described_class.can_transform?(0.6)).to be true
    end

    it 'returns true when confidence is above 0.6' do
      expect(described_class.can_transform?(0.8)).to be true
    end

    it 'returns false when confidence is below 0.6' do
      expect(described_class.can_transform?(0.59)).to be false
    end
  end

  describe '.can_self_modify?' do
    it 'returns true when confidence is exactly 0.8' do
      expect(described_class.can_self_modify?(0.8)).to be true
    end

    it 'returns true when confidence is above 0.8' do
      expect(described_class.can_self_modify?(0.95)).to be true
    end

    it 'returns false when confidence is below 0.8' do
      expect(described_class.can_self_modify?(0.79)).to be false
    end
  end
end
