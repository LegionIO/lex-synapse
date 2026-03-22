# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/challenge'

RSpec.describe Legion::Extensions::Synapse::Helpers::Challenge do
  describe 'constants' do
    it 'defines VALID_VERDICTS' do
      expect(described_class::VALID_VERDICTS).to contain_exactly('support', 'challenge', 'abstain')
    end

    it 'defines VALID_CHALLENGER_TYPES' do
      expect(described_class::VALID_CHALLENGER_TYPES).to contain_exactly('conflict', 'llm')
    end

    it 'defines VALID_OUTCOMES' do
      expect(described_class::VALID_OUTCOMES).to contain_exactly('correct', 'incorrect')
    end

    it 'defines IMPACT_WEIGHTS' do
      expect(described_class::IMPACT_WEIGHTS).to include(
        'llm_transform' => 0.7, 'route_change' => 0.8
      )
    end

    it 'defines DEFAULT_SETTINGS with expected keys' do
      expect(described_class::DEFAULT_SETTINGS).to include(
        enabled: true, impact_threshold: 0.3,
        auto_accept_threshold: 0.85, auto_reject_threshold: 0.15
      )
    end
  end

  describe '.settings' do
    context 'when no override configured' do
      before do
        allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'challenge').and_return(nil)
      end

      it 'returns defaults' do
        expect(described_class.settings[:impact_threshold]).to eq(0.3)
      end
    end

    context 'when override configured' do
      before do
        allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'challenge').and_return(
          { 'impact_threshold' => 0.5, 'enabled' => false }
        )
      end

      it 'merges with defaults' do
        result = described_class.settings
        expect(result[:impact_threshold]).to eq(0.5)
        expect(result[:enabled]).to be false
        expect(result[:auto_accept_threshold]).to eq(0.85)
      end
    end
  end

  describe '.enabled?' do
    it 'returns true by default' do
      allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'challenge').and_return(nil)
      expect(described_class.enabled?).to be true
    end
  end

  describe '.above_impact_threshold?' do
    before { allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'challenge').and_return(nil) }

    it('returns true when above') { expect(described_class.above_impact_threshold?(0.5)).to be true }
    it('returns false when below') { expect(described_class.above_impact_threshold?(0.1)).to be false }
    it('returns true at boundary') { expect(described_class.above_impact_threshold?(0.3)).to be true }
  end
end
