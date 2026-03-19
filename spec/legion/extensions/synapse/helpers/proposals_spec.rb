# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/proposals'

RSpec.describe Legion::Extensions::Synapse::Helpers::Proposals do
  describe 'constants' do
    it 'defines VALID_PROPOSAL_TYPES' do
      expect(described_class::VALID_PROPOSAL_TYPES).to include('llm_transform', 'attention_mutation',
                                                                'transform_mutation', 'route_change')
    end

    it 'defines VALID_TRIGGERS' do
      expect(described_class::VALID_TRIGGERS).to include('reactive', 'proactive')
    end

    it 'defines VALID_STATUSES' do
      expect(described_class::VALID_STATUSES).to include('pending', 'approved', 'rejected', 'applied', 'expired')
    end

    it 'defines DEFAULT_SETTINGS' do
      expect(described_class::DEFAULT_SETTINGS).to include(
        enabled: true, reactive: true, proactive: true,
        proactive_interval: 300, max_per_run: 3
      )
    end
  end

  describe '.settings' do
    context 'when Legion::Settings returns a hash' do
      before do
        allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'proposals').and_return(
          { 'enabled' => false, 'max_per_run' => 5 }
        )
      end

      it 'merges with defaults' do
        result = described_class.settings
        expect(result[:enabled]).to be false
        expect(result[:max_per_run]).to eq(5)
        expect(result[:proactive_interval]).to eq(300)
      end
    end

    context 'when Legion::Settings returns nil' do
      before do
        allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'proposals').and_return(nil)
      end

      it 'returns defaults' do
        result = described_class.settings
        expect(result[:enabled]).to be true
        expect(result[:max_per_run]).to eq(3)
      end
    end
  end

  describe '.enabled?' do
    it 'returns true when enabled setting is true' do
      allow(described_class).to receive(:settings).and_return(described_class::DEFAULT_SETTINGS)
      expect(described_class.enabled?).to be true
    end

    it 'returns false when enabled setting is false' do
      allow(described_class).to receive(:settings).and_return(described_class::DEFAULT_SETTINGS.merge(enabled: false))
      expect(described_class.enabled?).to be false
    end
  end

  describe '.reactive?' do
    it 'returns true when both enabled and reactive are true' do
      allow(described_class).to receive(:settings).and_return(described_class::DEFAULT_SETTINGS)
      expect(described_class.reactive?).to be true
    end

    it 'returns false when enabled is false' do
      allow(described_class).to receive(:settings).and_return(described_class::DEFAULT_SETTINGS.merge(enabled: false))
      expect(described_class.reactive?).to be false
    end
  end

  describe '.proactive?' do
    it 'returns true when both enabled and proactive are true' do
      allow(described_class).to receive(:settings).and_return(described_class::DEFAULT_SETTINGS)
      expect(described_class.proactive?).to be true
    end

    it 'returns false when proactive is false' do
      allow(described_class).to receive(:settings).and_return(described_class::DEFAULT_SETTINGS.merge(proactive: false))
      expect(described_class.proactive?).to be false
    end
  end

  describe '.llm_engine_options' do
    it 'returns default engine options' do
      allow(described_class).to receive(:settings).and_return(described_class::DEFAULT_SETTINGS)
      opts = described_class.llm_engine_options
      expect(opts[:temperature]).to eq(0.3)
      expect(opts[:max_tokens]).to eq(1024)
    end
  end
end
