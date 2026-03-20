# frozen_string_literal: true

RSpec.describe WildSkillopsRegistry::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'sets max_skills to 1000' do
      expect(config.max_skills).to eq(1_000)
    end

    it 'sets max_versions_per_skill to 50' do
      expect(config.max_versions_per_skill).to eq(50)
    end

    it 'sets health_stale_threshold_hours to 24' do
      expect(config.health_stale_threshold_hours).to eq(24)
    end

    it 'sets allowed_lifecycle_states to the standard set' do
      expect(config.allowed_lifecycle_states).to match_array(%i[draft active deprecated retired])
    end

    it 'sets allowed_health_states to the standard set' do
      expect(config.allowed_health_states).to match_array(%i[available degraded unavailable unknown])
    end

    it 'is not frozen by default' do
      expect(config.frozen?).to be false
    end
  end

  describe 'setters' do
    it 'sets max_skills to a valid positive integer' do
      config.max_skills = 500
      expect(config.max_skills).to eq(500)
    end

    it 'raises ArgumentError for zero max_skills' do
      expect { config.max_skills = 0 }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError for negative max_skills' do
      expect { config.max_skills = -10 }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError for string max_skills' do
      expect { config.max_skills = 'lots' }.to raise_error(ArgumentError)
    end

    it 'sets max_versions_per_skill' do
      config.max_versions_per_skill = 10
      expect(config.max_versions_per_skill).to eq(10)
    end

    it 'sets health_stale_threshold_hours' do
      config.health_stale_threshold_hours = 48
      expect(config.health_stale_threshold_hours).to eq(48)
    end

    it 'sets allowed_lifecycle_states from an array of symbols' do
      config.allowed_lifecycle_states = %i[draft active]
      expect(config.allowed_lifecycle_states).to eq(%i[draft active])
    end

    it 'raises ArgumentError for empty allowed_lifecycle_states' do
      expect { config.allowed_lifecycle_states = [] }.to raise_error(ArgumentError)
    end

    it 'sets allowed_health_states from an array of symbols' do
      config.allowed_health_states = %i[available unknown]
      expect(config.allowed_health_states).to eq(%i[available unknown])
    end
  end

  describe '#freeze!' do
    it 'marks configuration as frozen' do
      config.freeze!
      expect(config.frozen?).to be true
    end

    it 'prevents further modification after freeze' do
      config.freeze!
      expect do
        config.max_skills = 5
      end.to raise_error(WildSkillopsRegistry::ConfigurationFrozenError)
    end

    it 'returns self for chaining' do
      expect(config.freeze!).to eq(config)
    end
  end

  describe 'module-level interface' do
    it 'provides WildSkillopsRegistry.configuration' do
      expect(WildSkillopsRegistry.configuration).to be_a(described_class)
    end

    it 'supports WildSkillopsRegistry.configure block' do
      WildSkillopsRegistry.configure { |c| c.max_skills = 42 }
      expect(WildSkillopsRegistry.configuration.max_skills).to eq(42)
    end

    it 'reset_configuration! restores defaults' do
      WildSkillopsRegistry.configure { |c| c.max_skills = 42 }
      WildSkillopsRegistry.reset_configuration!
      expect(WildSkillopsRegistry.configuration.max_skills).to eq(1_000)
    end
  end
end
