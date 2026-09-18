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
    # Currency symbol, a "<digits>k" shorthand (e.g. "80k", too short to trip
    # the digit-run check below), or a run of 3+ consecutive digits (comma
    # thousands separators like "230,000" always contain one either side of
    # the comma).
    COMPENSATION = /[$£€]|\d+k\b|\d{3,}/i
    IGNORED_DOMAIN_HOSTS = %w[news.ycombinator.com].freeze

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

      # Everything before the first paragraph break.
      def header
        @header ||= text.split(/<p>/).first.to_s
      end

      def segments
        @segments ||= header.split("|").map(&:strip)
      end

      def name
        return @name if defined?(@name)

        raw = segments.first.to_s.sub(/\(.*\z/, "").strip
        @name = raw.match?(/\A[[:alnum:]]/) && segments.length > 1 ? raw : nil
      end

      # Algolia renders every URL in the header as an anchor, so an href
      # attribute is the primary signal; a bare URL is a fallback for headers
      # that skip the anchor. Either way, HN's own permalink is chrome, not
      # the company's site.
      def domain
        return @domain if defined?(@domain)

        url = first_company_url(header.scan(/href="(https?:\/\/[^"]+)"/).flatten) ||
              first_company_url(header.scan(/https?:\/\/[^\s()<>"]+/))
        @domain = url && URI.parse(url).host&.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        @domain = nil
      end

      def first_company_url(urls)
        urls.find { |url| !IGNORED_DOMAIN_HOSTS.include?(URI.parse(url).host&.downcase) }
      end

      def location
        return @location if defined?(@location)

        # segments[1] is conventionally the job title ("Company | Title | ...");
        # exclude it so a comma inside a title (e.g. "Backend Engineer, Platform")
        # never reads as a location. With fewer than 3 segments there's no
        # separate title slot to exclude, so fall back to the original range.
        candidates = segments.length >= 3 ? segments[2..] : segments[1..]
        @location = candidates.to_a.reverse.find do |segment|
          segment.present? && !segment.match?(LOCATION_NOISE) && segment.length < 60 &&
            segment.include?(",") && !segment.match?(COMPENSATION)
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
