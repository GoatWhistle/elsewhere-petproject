# Forced, not defaulted: docker-compose exports RAILS_ENV=development for the app
# service, and `||=` would let the suite run against the development database.
ENV["RAILS_ENV"] = "test"
# Cleared for the same reason: .env now reaches the container, so a developer with Ollama running would
# otherwise have the suite talk to a live model. A spec that wants an answer passes `response:`; every
# other spec must take the deterministic path, and the persona regression suite must not vary by model.
ENV.delete("LLM_BASE_URL")
ENV.delete("LLM_MODEL")
ENV.delete("LLM_API_KEY")
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.before { Elsewhere::Store.reset! }
end
