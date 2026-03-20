# frozen_string_literal: true

require_relative 'lib/wild_skillops_registry/version'

Gem::Specification.new do |spec|
  spec.name = 'wild-skillops-registry'
  spec.version = WildSkillopsRegistry::VERSION
  spec.authors = ['Intent Solutions']
  spec.summary = 'Registry and discovery layer for skills/capabilities across the wild ecosystem'
  spec.description = 'Registry, versioning, health tracking, and governance library for ' \
                     'skills and capabilities published by wild ecosystem repositories. ' \
                     'Provides discoverability, dependency mapping, and lifecycle management.'
  spec.homepage = 'https://github.com/jeremylongshore/wild-skillops-registry'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.metadata['rubygems_mfa_required'] = 'true'
end
