require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module Elsewhere
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.active_job.queue_adapter = :sidekiq
    config.active_record.schema_format = :sql
    config.active_record.dump_schemas = :all
    config.autoload_paths += Dir[root.join("packs/*/lib")]
    config.eager_load_paths += Dir[root.join("packs/*/lib")]
  end
end
