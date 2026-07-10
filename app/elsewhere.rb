require "json"
require "webrick"
require_relative "values"
require_relative "ai/task"
require_relative "elsewhere/store"
require_relative "../packs/supply/lib/supply"
require_relative "../packs/planning/lib/planning"
require_relative "../packs/foresight/lib/foresight"
require_relative "elsewhere/http_app"

module Elsewhere
  class Server
    def initialize(port: 3000)
      @port = port
    end

    def start
      server = WEBrick::HTTPServer.new(Port: @port, AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN))
      server.mount_proc "/" do |request, response|
        app = Elsewhere::HTTPApp.new(request, response)
        app.call
      end
      trap("INT") { server.shutdown }
      puts "Elsewhere API listening on http://localhost:#{@port}"
      server.start
    end
  end
end

