# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/version'

RSpec.describe Legion::Extensions::Synapse do
  it 'has a version number' do
    expect(Legion::Extensions::Synapse::VERSION).not_to be_nil
  end

  it 'has a semantic version string' do
    expect(Legion::Extensions::Synapse::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
