# frozen_string_literal: true

module WildSkillopsRegistry
  # Validated, freeze-on-configure configuration for the registry.
  class Configuration
    ALLOWED_LIFECYCLE_STATES = %i[draft active deprecated retired].freeze
    ALLOWED_HEALTH_STATES    = %i[available degraded unavailable unknown].freeze

    attr_reader :max_skills,
                :max_versions_per_skill,
                :health_stale_threshold_hours,
                :allowed_lifecycle_states,
                :allowed_health_states

    def initialize
      @max_skills                  = 1_000
      @max_versions_per_skill      = 50
      @health_stale_threshold_hours = 24
      @allowed_lifecycle_states    = ALLOWED_LIFECYCLE_STATES.dup
      @allowed_health_states       = ALLOWED_HEALTH_STATES.dup
      @frozen                      = false
    end

    def max_skills=(value)
      assert_mutable!
      raise ArgumentError, 'max_skills must be a positive Integer' unless value.is_a?(Integer) && value.positive?

      @max_skills = value
    end

    def max_versions_per_skill=(value)
      assert_mutable!
      unless value.is_a?(Integer) && value.positive?
        raise ArgumentError, 'max_versions_per_skill must be a positive Integer'
      end

      @max_versions_per_skill = value
    end

    def health_stale_threshold_hours=(value)
      assert_mutable!
      unless value.is_a?(Integer) && value.positive?
        raise ArgumentError, 'health_stale_threshold_hours must be a positive Integer'
      end

      @health_stale_threshold_hours = value
    end

    def allowed_lifecycle_states=(value)
      assert_mutable!
      raise ArgumentError, 'allowed_lifecycle_states must be an Array of Symbols' unless valid_symbol_array?(value)

      @allowed_lifecycle_states = value.map(&:to_sym)
    end

    def allowed_health_states=(value)
      assert_mutable!
      raise ArgumentError, 'allowed_health_states must be an Array of Symbols' unless valid_symbol_array?(value)

      @allowed_health_states = value.map(&:to_sym)
    end

    def freeze!
      @frozen = true
      self
    end

    def frozen?
      @frozen
    end

    private

    def assert_mutable!
      return unless @frozen

      raise ConfigurationFrozenError, 'Configuration is frozen and cannot be modified'
    end

    def valid_symbol_array?(value)
      value.is_a?(Array) && !value.empty? && value.all? { |v| v.is_a?(Symbol) || v.is_a?(String) }
    end
  end
end
