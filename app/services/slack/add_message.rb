# frozen_string_literal: true

module Slack
  # Turns the Slack message somebody pinned, or pasted a link to, into a task
  # on their team's list.
  #
  # One task per message: the channel and timestamp are its external id. A
  # message that is already on the list is left alone, so a redelivered event
  # changes nothing. One that was ticked off comes back to the top, because
  # pinning it again means it needs you again — the same rule as the inbox.
  # Either way a title somebody edited in Done stays as they wrote it.
  class AddMessage < ApplicationService
    # A Slack message can be an essay. The title is its opening, the notes the
    # whole thing.
    TITLE_LENGTH = 200

    # `thread_ts` is the thread a reply sits in, when the caller knows it — a
    # pasted link says; a 📌 does not, and Slack finds the thread from the
    # reply's own timestamp.
    #
    # `project` is one the person named in quick add ("WCH <link>"). It must
    # be one of the team's own: the caller looks it up through the team.
    def initialize(connection:, channel:, ts:, thread_ts: nil, project: nil)
      @connection = connection
      @team = connection.team
      @channel = channel.to_s
      @ts = ts.to_s
      @thread_ts = thread_ts.presence&.to_s
      @project = project
    end

    def call
      task = @team.tasks.find_or_initialize_by(source: "slack", external_id: external_id)
      return refile(task) if task.persisted? && !task.done?

      task.new_record? ? create(task) : reopen(task)
    rescue ActiveRecord::RecordNotUnique
      success(@team.tasks.find_by!(source: "slack", external_id: external_id)) # a second delivery beat us to it
    rescue Slack::Api::Unavailable
      raise # the job's retry policy takes it from here
    rescue Slack::Api::Error => e
      @connection.destroy! if e.message.in?(Slack::Api::REVOKED)
      failure(e.message)
    end

    private

    def external_id = "#{@channel}-#{@ts}"

    def create(task)
      message = fetch_message
      return failure("That message is gone.") if message.nil?

      fill(task, message)
      task.save!
      arrived(task)
    end

    # Already on the list. Naming a project files it there; nothing else
    # changes, so a redelivered 📌 is still a no-op.
    def refile(task)
      task.update!(project: @project) if @project && task.project != @project
      success(task)
    end

    def reopen(task)
      task.project = @project if @project
      task.reopen!
      arrived(task)
    end

    def arrived(task)
      task.broadcast_arrival
      success(task)
    end

    def fill(task, message)
      text = plain(message["text"])
      title = text.lines.first.to_s.squish.truncate(TITLE_LENGTH, separator: " ").presence || "Slack message"

      task.assign_attributes(
        title: title,
        notes: (text.strip.first(10_000) unless text.squish == title),
        url: permalink,
        project: @project,
        created_by: @connection.user
      )
    end

    # The message itself, whether it is in the channel or inside a thread.
    def fetch_message
      in_channel = api.call("conversations.history", channel: @channel, oldest: @ts, latest: @ts, inclusive: true, limit: 1)
      matching(in_channel) || matching(api.call("conversations.replies", channel: @channel, ts: @thread_ts || @ts, oldest: @ts, inclusive: true, limit: 2))
    end

    # A thread's replies always start with its parent, so look by timestamp.
    def matching(response) = response["messages"].to_a.find { |message| message["ts"] == @ts }

    def permalink = api.call("chat.getPermalink", channel: @channel, message_ts: @ts)["permalink"]

    # Slack's markup, as a person would read it: links become their labels,
    # mentions become names.
    def plain(text)
      text.to_s
          .gsub(/<#[A-Z0-9]+\|([^>]*)>/) { "##{$1}" }
          .gsub(/<@([A-Z0-9]+)(?:\|[^>]*)?>/) { "@#{name_of($1)}" }
          .gsub(/<!subteam\^[A-Z0-9]+\|([^>]*)>/) { $1 }
          .gsub(/<!(here|channel|everyone)(?:\|[^>]*)?>/) { "@#{$1}" }
          .gsub(/<[^>|]*\|([^>]*)>/) { $1 }
          .gsub(/<([^>]*)>/) { $1 }
          .then { |plain| CGI.unescapeHTML(plain) }
    end

    def name_of(slack_user_id)
      @names ||= {}
      @names[slack_user_id] ||= begin
        profile = api.call("users.info", user: slack_user_id).dig("user", "profile").to_h
        profile["display_name"].presence || profile["real_name"].presence || "someone"
      rescue Slack::Api::Unavailable
        raise
      rescue Slack::Api::Error
        "someone"
      end
    end

    def api = @api ||= Slack::Api.new(@connection.access_token)
  end
end
