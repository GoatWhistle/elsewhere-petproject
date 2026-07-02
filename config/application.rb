# frozen_string_literal: true

# This file is intentionally Rails-shaped. In environments where Rails is
# installed, `config/environment.rb` boots the same contexts; the Phase 0
# executable remains usable with the standard-library adapter.
module Elsewhere
  class Application
    def self.config; @config ||= {}; end
  end
end

