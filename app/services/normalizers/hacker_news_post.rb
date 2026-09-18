module Normalizers
  # Parses a Hacker News "Who is hiring?" job post into canonical company
  # attributes plus the evidence backing each one.
  #
  # The conventional header is "Company (url) | Role | REMOTE | Location", but
  # it is a convention rather than a rule. We extract what is confidently
  # present and stay silent about the rest: a wrong attribute is worse than a
  # missing one, because a wrong one gets scored.
  class HackerNewsPost
    SOURCE_KEY = "hn_who_is_hiring".freeze
    LOCATION_NOISE = /\A(remote|onsite|visa|interns?|full[- ]time|part[- ]time)\z/i

    def initialize(raw_hit)
      @raw_hit = raw_hit
      @payload = raw_hit.payload
    end

    def call
      return blank_result if name.blank?

      Result.new(
        company_attrs: { name: name, domain: domain, location: location }.compact,
        identifiers: identifiers,
        evidence_attrs: evidence_attrs
      )
    end

    private
      def blank_result = Result.new(company_attrs: {}, identifiers: [], evidence_attrs: [])

      def text
        @text ||= CGI.unescapeHTML(@payload["comment_text"].to_s)
      end

      # The header is everything before the first paragraph break.
      def segments
        @segments ||= text.split(/<p>/).first.to_s.split("|").map(&:strip)
      end

      def name
        return @name if defined?(@name)

        raw = segments.first.to_s.sub(/\(.*\z/, "").strip
        @name = raw.match?(/\A[[:alnum:]]/) && segments.length > 1 ? raw : nil
      end

      def domain
        return @domain if defined?(@domain)

        url = segments.first.to_s[/\((https?:\/\/[^)\s]+)\)/, 1]
        @domain = url && URI.parse(url).host&.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        @domain = nil
      end

      def location
        @location ||= segments[1..].to_a.reverse.find do |segment|
          segment.present? && !segment.match?(LOCATION_NOISE) && segment.length < 60 && segment.include?(",")
        end
      end

      def identifiers
        list = []
        list << { kind: "domain", value: domain } if domain.present?
        list << { kind: "normalized_name", value: name.downcase.strip } if name.present?
        list
      end

      def source_url
        "https://news.ycombinator.com/item?id=#{@payload['objectID']}"
      end

      def evidence_attrs
        { "name" => name, "domain" => domain, "location" => location }.compact.map do |attribute, value|
          {
            attribute_name: attribute,
            value: value,
            source_key: SOURCE_KEY,
            source_url: source_url,
            fetched_at: @raw_hit.fetched_at,
            raw_hit_id: @raw_hit.id,
            confidence: 0.8
          }
        end
      end
  end
end
