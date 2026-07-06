ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Force ActionCable to load so turbo-rails' `assert_turbo_stream_broadcasts` helper
# is reliably available. That helper is included via a nested
# `on_load(:action_cable) { on_load(:active_support_test_case) { … } }` hook, so it
# only appears once ActionCable::Server::Base loads. Left lazy, its availability
# depends on test execution order (a latent flake). Loading it here makes it
# deterministic.
ActionCable::Server::Base

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Seed the Phase 1 monster species (36 forms) via the shared seeder — the same
    # code path the `monsters:seed` rake task runs. Rolled back with each test's
    # transaction; idempotent so it is safe to call in every setup.
    def seed_monster_species!
      MonsterSeeder.seed_phase1!
    end

    # Seed the 13 badge catalog rows (needed to grant/trigger badges).
    def seed_badges!
      Badge::KEYS.each do |key|
        Badge.find_or_create_by!(key: key) { |badge| badge.name = key }
      end
    end
  end
end
