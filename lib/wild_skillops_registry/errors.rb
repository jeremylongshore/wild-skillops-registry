# frozen_string_literal: true

module WildSkillopsRegistry
  # Base error for all registry errors
  class Error < StandardError; end

  # Raised when a skill registration payload is invalid
  class ValidationError < Error; end

  # Raised when a referenced skill does not exist in the registry
  class NotFoundError < Error; end

  # Raised when a duplicate skill name is registered without an explicit update
  class DuplicateSkillError < Error; end

  # Raised when a lifecycle transition is not permitted
  class LifecycleError < Error; end

  # Raised when attempting to mutate a frozen configuration
  class ConfigurationFrozenError < Error; end

  # Raised when the registry exceeds its configured capacity
  class RegistryCapacityError < Error; end

  # Raised when a skill version limit is exceeded
  class VersionCapacityError < Error; end
end
