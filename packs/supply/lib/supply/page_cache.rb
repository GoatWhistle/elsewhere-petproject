require "digest"
require "fileutils"
require "json"
require "time"

module Supply
  # Raw responses on disk, keyed by URL. The first pass pays for every page and every pass after it — a parser
  # fix, a new field, a fresh database — reads from disk and sends nothing.
  class PageCache
    Entry = Struct.new(:body, :status, :fetched_at, :url, :source, keyword_init: true) do
      def from_cache? = source == :cache
    end

    def initialize(root: nil)
      @root = root || ENV.fetch("SUPPLY_HARVEST_CACHE", File.join(Dir.pwd, "tmp", "supply", "harvest"))
    end

    attr_reader :root

    def read(url)
      meta_path = path_for(url, "json")
      return nil unless File.exist?(meta_path)

      meta = JSON.parse(File.read(meta_path))
      body_path = path_for(url, "html")
      return nil unless File.exist?(body_path)

      Entry.new(body: File.read(body_path, encoding: "UTF-8"), status: meta["status"],
                fetched_at: meta["fetched_at"], url: url, source: :cache)
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def write(url, status:, body:)
      FileUtils.mkdir_p(File.dirname(path_for(url, "html")))
      File.write(path_for(url, "html"), body.to_s)
      fetched_at = Time.now.utc.iso8601
      File.write(path_for(url, "json"), JSON.pretty_generate("url" => url, "status" => status, "fetched_at" => fetched_at))
      Entry.new(body: body, status: status, fetched_at: fetched_at, url: url, source: :network)
    end

    # Cached entries are returned untouched; only a miss reaches the block. `refresh: true` is the escape hatch
    # for "the source changed", and it is a deliberate act, never a default.
    def fetch(url, refresh: false)
      unless refresh
        hit = read(url)
        return hit if hit
      end
      yield
    end

    def path_for(url, extension)
      digest = Digest::SHA1.hexdigest(url)
      host = URI.parse(url).host.to_s.gsub(/[^a-z0-9.\-]/i, "_")
      File.join(@root, host, "#{digest}.#{extension}")
    rescue URI::InvalidURIError
      File.join(@root, "unparsed", "#{Digest::SHA1.hexdigest(url)}.#{extension}")
    end
  end
end
