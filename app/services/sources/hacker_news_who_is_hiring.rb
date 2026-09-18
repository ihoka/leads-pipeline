require "net/http"

module Sources
  # Sources job posts from the monthly "Ask HN: Who is hiring?" thread via the
  # public Algolia HN API. Free, unauthenticated, geography-agnostic, and dense
  # with funded startups actively looking for developers.
  class HackerNewsWhoIsHiring < Adapter
    ENDPOINT = "https://hn.algolia.com/api/v1/search_by_date".freeze
    HIRING_TITLE = /who is hiring/i
    DEFAULT_MAX_PAGES = 5
    PAGE_SIZE = 100

    ThreadNotFound = Class.new(StandardError)
    RequestFailed = Class.new(StandardError)

    def self.key = "hn_who_is_hiring"

    def self.manifest
      Manifest.new(
        accepted_params: [ :max_pages ],
        returned_fields: [ :comment_text, :author, :created_at ],
        cost_cents_per_call: 0,
        risk_level: :none
      )
    end

    def search(params)
      story_id = latest_hiring_story_id
      max_pages = params.fetch(:max_pages, DEFAULT_MAX_PAGES)

      collect_comments(story_id, max_pages).map do |comment|
        Hit.new(
          source_uid: comment["objectID"],
          payload: comment,
          observed_at: Time.parse(comment["created_at"])
        )
      end
    end

    private
      # The whoishiring account posts two threads at the same timestamp each
      # month; only "Who is hiring?" carries job posts.
      def latest_hiring_story_id
        stories = get(tags: "story,author_whoishiring", hitsPerPage: 10).fetch("hits", [])
        story = stories.find { |hit| hit["title"].to_s.match?(HIRING_TITLE) }
        raise ThreadNotFound, "no 'Who is hiring?' thread found" if story.nil?

        story["objectID"]
      end

      # Only comments whose parent is the story itself are job posts; the rest
      # are replies and discussion.
      def collect_comments(story_id, max_pages)
        comments = []

        (0...max_pages).each do |page|
          body = get(tags: "comment,story_#{story_id}", hitsPerPage: PAGE_SIZE, page: page)
          hits = body.fetch("hits", [])
          comments.concat(hits.select { |hit| hit["parent_id"].to_s == hit["story_id"].to_s })

          break if hits.empty? || page >= body.fetch("nbPages", 1) - 1
        end

        comments
      end

      def get(query)
        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(query)
        response = Net::HTTP.get_response(uri)

        unless response.is_a?(Net::HTTPSuccess)
          raise RequestFailed, "HN API returned #{response.code} for #{uri}"
        end

        JSON.parse(response.body)
      end
  end
end
