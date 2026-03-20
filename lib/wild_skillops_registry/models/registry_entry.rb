# frozen_string_literal: true

module WildSkillopsRegistry
  module Models
    # A full registry entry combining a skill with its associated metadata.
    # This is the canonical read-side view of a skill in the registry.
    class RegistryEntry
      attr_reader :skill, :versions, :health_status, :owner, :dependencies

      def initialize(skill:, versions: [], health_status: nil, owner: nil, dependencies: [])
        raise ValidationError, 'skill must be a Skill instance' unless skill.is_a?(Skill)

        @skill         = skill
        @versions      = versions
        @health_status = health_status
        @owner         = owner
        @dependencies  = dependencies
      end

      def name
        @skill.name
      end

      def current_version
        @skill.version
      end

      def lifecycle_state
        @skill.lifecycle_state
      end

      def healthy?
        @health_status&.state == :available
      end

      def to_h
        {
          skill: @skill.to_h,
          versions: @versions.map(&:to_h),
          health_status: @health_status&.to_h,
          owner: @owner&.to_h,
          dependencies: @dependencies.map(&:to_h)
        }
      end
    end
  end
end
