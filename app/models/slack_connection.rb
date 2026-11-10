# frozen_string_literal: true

# One person's Slack account, linked to one team. Reacting to a Slack message
# with EMOJI turns it into a task on that team's list. See Slack::EventsController.
#
# The token is a Slack *user* token: it reads the messages its owner can read,
# so it is encrypted at rest and only ever used to fetch the one message they
# reacted to.
class SlackConnection < ApplicationRecord
  include TenantScoped

  # 📌 — "pin this to my list".
  EMOJI = "pushpin"

  belongs_to :user

  # A message's "Copy link": its channel, then its timestamp without the dot.
  # A reply in a thread also carries the thread's own timestamp.
  MESSAGE_LINK = %r{\Ahttps://(?:[a-z0-9-]+\.)+slack\.com/archives/([A-Z0-9]+)/p(\d{10})(\d{6})(?:\?(\S*))?\z}

  encrypts :access_token

  validates :slack_team_id, :slack_user_id, :access_token, presence: true

  # The channel and timestamps in a Slack message link, ready for
  # Slack::AddMessage, or nil for anything else.
  def self.message_in(text)
    match = text.to_s.strip.match(MESSAGE_LINK) or return

    thread_ts = Rack::Utils.parse_query(match[4].to_s)["thread_ts"].to_s
    { channel: match[1], ts: "#{match[2]}.#{match[3]}", thread_ts: (thread_ts if thread_ts.match?(/\A\d+\.\d+\z/)) }
  end

  # Every Slack setting this needs, from credentials. Blank means the Slack
  # section of the connections page says so and nothing else changes.
  def self.configured?
    Rails.configuration.x.slack_client_id.present? &&
      Rails.configuration.x.slack_client_secret.present? &&
      Rails.configuration.x.slack_signing_secret.present?
  end
end
