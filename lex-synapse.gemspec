# frozen_string_literal: true

require_relative 'lib/legion/extensions/synapse/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-synapse'
  spec.version       = Legion::Extensions::Synapse::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']

  spec.summary       = 'Cognitive routing layer for LegionIO task chains'
  spec.description   = 'Attention, transformation, and routing with confidence scoring, pain signals, homeostasis, and self-governance'
  spec.homepage      = 'https://github.com/LegionIO/lex-synapse'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/LegionIO/lex-synapse'
  spec.metadata['documentation_uri'] = 'https://github.com/LegionIO/lex-synapse'
  spec.metadata['changelog_uri'] = 'https://github.com/LegionIO/lex-synapse/blob/main/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/LegionIO/lex-synapse/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'lex-conditioner', '>= 0.3.0'
  spec.add_dependency 'lex-transformer', '>= 0.2.0'
end
