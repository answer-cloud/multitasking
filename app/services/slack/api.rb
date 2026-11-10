# frozen_string_literal: true

require "net/http"

module Slack
  # The few Slack Web API calls this app makes, over plain Net::HTTP. Slack's
  # API is form posts in, JSON out, with `ok: false` and an error code on
  # failure — small enough that a gem would be more to keep up than this.
  class Api
    # Slack said no, and will say no again: a revoked token, a deleted message.
    class Error < StandardError; end

    # Slack is busy or out of reach. Worth trying again later.
    class Unavailable < Error; end

    # The token no longer works. The connection behind it is dead.
    REVOKED = %w[token_revoked token_expired invalid_auth account_inactive not_authed].freeze

    def initialize(token = nil)
      @token = token
    end

    def call(method, **params)
      response = post(method, params.compact)
      raise Unavailable, "#{method}: HTTP #{response.code}" if response.code == "429" || response.code.start_with?("5")

      body = JSON.parse(response.body)
      raise Error, body["error"].to_s unless body["ok"]

      body
    rescue JSON::ParserError
      raise Unavailable, "#{method}: not JSON"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Unavailable, "#{method}: #{e.class}"
    end

    private

    def post(method, params)
      uri = URI("https://slack.com/api/#{method}")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@token}" if @token
      request.set_form_data(params)

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
    end
  end
end
