# frozen_string_literal: true

require_relative 'wild_skillops_registry/version'
require_relative 'wild_skillops_registry/errors'
require_relative 'wild_skillops_registry/configuration'

# Models
require_relative 'wild_skillops_registry/models/skill'
require_relative 'wild_skillops_registry/models/skill_version'
require_relative 'wild_skillops_registry/models/dependency'
require_relative 'wild_skillops_registry/models/health_status'
require_relative 'wild_skillops_registry/models/owner'
require_relative 'wild_skillops_registry/models/registry_entry'

# Registry
require_relative 'wild_skillops_registry/registry/store'
require_relative 'wild_skillops_registry/registry/registrar'
require_relative 'wild_skillops_registry/registry/finder'

# Versioning
require_relative 'wild_skillops_registry/versioning/version_manager'
require_relative 'wild_skillops_registry/versioning/changelog_builder'

# Health
require_relative 'wild_skillops_registry/health/tracker'
require_relative 'wild_skillops_registry/health/aggregator'

# Governance
require_relative 'wild_skillops_registry/governance/lifecycle_manager'
require_relative 'wild_skillops_registry/governance/ownership_resolver'

# Discovery
require_relative 'wild_skillops_registry/discovery/tag_index'
require_relative 'wild_skillops_registry/discovery/search_engine'

# Export
require_relative 'wild_skillops_registry/export/json_exporter'
require_relative 'wild_skillops_registry/export/markdown_exporter'

# WildSkillopsRegistry is the registry and discovery layer for skills/capabilities
# across all wild ecosystem repositories.
module WildSkillopsRegistry
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # Build a fully-wired registry instance.
    def build
      store = Registry::Store.new
      tag_index = Discovery::TagIndex.new
      RegistryFacade.new(**build_components(store, tag_index))
    end

    private

    def build_components(store, tag_index) # rubocop:disable Metrics/MethodLength
      lifecycle_manager = Governance::LifecycleManager.new
      version_manager = Versioning::VersionManager.new(store: store)
      registrar = Registry::Registrar.new(
        store: store,
        version_manager: version_manager,
        lifecycle_manager: lifecycle_manager,
        tag_index: tag_index
      )
      {
        store: store,
        tag_index: tag_index,
        registrar: registrar,
        finder: Registry::Finder.new(store: store, tag_index: tag_index),
        version_manager: version_manager,
        changelog_builder: Versioning::ChangelogBuilder.new(version_manager: version_manager),
        health_tracker: Health::Tracker.new(store: store),
        health_aggregator: Health::Aggregator.new(store: store),
        lifecycle_manager: lifecycle_manager,
        ownership_resolver: Governance::OwnershipResolver.new(store: store),
        search_engine: Discovery::SearchEngine.new(finder: Registry::Finder.new(store: store, tag_index: tag_index)),
        json_exporter: Export::JsonExporter.new(store: store),
        markdown_exporter: Export::MarkdownExporter.new(store: store)
      }
    end
  end

  # Convenience facade providing a single access point for all registry operations.
  class RegistryFacade
    attr_reader :store, :registrar, :finder, :version_manager,
                :changelog_builder, :health_tracker, :health_aggregator,
                :lifecycle_manager, :ownership_resolver, :search_engine,
                :json_exporter, :markdown_exporter, :tag_index

    def initialize(**kwargs)
      kwargs.each { |key, value| instance_variable_set(:"@#{key}", value) }
    end
  end
end
