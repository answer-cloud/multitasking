# frozen_string_literal: true

module Inbox
  # Where other tools push tasks in: Claude Code and Codex hooks today, and the
  # Chrome extension and email later. Slack has its own door; see
  # Slack::EventsController.
  #
  # There is no session here. The caller proves who it is with a person's
  # inbox token, sent as a bearer token — never in the URL, where it would end
  # up in server logs and browser history. The token is a membership's, so it
  # says both which team is written to and whose list the task lands on.
  #
  # A caller that sends an `assignee` — a colleague's name or email — puts the
  # task on that person's list instead. This is how "assign Sam: fix the
  # navbar", said to Claude, reaches Sam; see script/agent-hook. A name that
  # picks out nobody, or more than one person, is refused rather than guessed
  # at. A `project`, by name, files it.
  #
  # A caller that sends an `external_id` (a Claude session, a Codex thread)
  # gets one task per id. A second ping updates that task, moves it back to the
  # top and reopens it, because "the agent needs you again" is news even if you
  # ticked it off an hour ago.
  #
  # A caller that sends a `directory` — the repository an agent was working
  # in — gets the task filed under that folder's project, made on the spot if
  # this is the first task from there. A task somebody has already filed by
  # hand stays where they put it.
  class TasksController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    PUSHED_SOURCES = (Task::SOURCES.keys - Task::IN_APP_SOURCES).freeze

    rate_limit to: 120, within: 1.minute, by: -> { request.remote_ip }

    before_action :set_membership
    before_action :set_assignee

    def create
      task = find_or_build_task
      task.assign_attributes(pushed_attributes)
      task.completed_at = nil
      task.last_activity_at = Time.current
      task.put_on_top if task.persisted?
      task.project ||= named_project || projects.claim_directory(params[:directory])

      if task.save
        task.broadcast_arrival
        render_saved(task)
      else
        render json: { errors: task.errors.full_messages }, status: :unprocessable_content
      end
    end

    private

    # The assignee's name goes back so the caller can say whose list it is on.
    def render_saved(task)
      render json: { id: task.id, created: task.previously_new_record?, assignee: task.assignee&.name },
             status: task.previously_new_record? ? :created : :ok
    end

    # The one lookup here that does not start from a team: the token is what
    # says which team this is.
    def set_membership
      @membership = authenticate_with_http_token { |token, _| Membership.find_by(inbox_token: token) if token.present? }
      return head :unauthorized if @membership.nil?

      @team = @membership.team
    end

    # Whose list this is for: the person named, found through the team, or
    # the token's own.
    def set_assignee
      name = params[:assignee].to_s.squish
      return @assignee = @membership.user if name.empty?

      @assignee = @team.memberships.named(name)&.user
      return if @assignee

      people = @team.memberships.ordered.includes(:user).map { |membership| membership.user.name }
      render json: { errors: [ "Nobody on this team is called “#{name.first(100)}”. The team is: #{people.to_sentence}." ] },
             status: :unprocessable_content
    end

    # The projects the token's owner can see. A hook cannot file a task under
    # a project its owner could not open, or learn that one exists.
    def projects = @team.projects.visible_to(@membership)

    def named_project = projects.named(params[:project])

    # Started from the team, like every other tenant query.
    def find_or_build_task
      external_id = params[:external_id].presence&.to_s&.first(255)
      return new_task if external_id.nil?

      task = @team.tasks.find_by(source: pushed_source, external_id: external_id) || handed_off_task || new_task
      task.external_id = external_id
      # A session that pings again stays on the list it is on, unless this
      # ping names somebody.
      task.assignee = @assignee if params[:assignee].present?
      task
    end

    def new_task = @team.tasks.new(created_by: @membership.user, assignee: @assignee)

    # The task somebody handed to this agent from its row, coming back from the
    # session that started on it: that session's first prompt begins with the
    # task's title. Taking it over keeps one task, not the one you handed off
    # plus a second saying the agent is done with it. A prompt edited before
    # it was sent matches nothing, and the agent's task arrives on its own.
    def handed_off_task
      prompt = params[:prompt].to_s.squish
      return if prompt.empty?

      @team.tasks.pending.where(handed_to: pushed_source, external_id: nil, handed_at: 1.day.ago..)
           .order(handed_at: :desc)
           .detect { |task| prompt.start_with?(task.title.squish) }
    end

    def pushed_attributes
      {
        title: params[:title].to_s.squish.first(Task::TITLE_LIMIT),
        notes: params[:notes].presence&.to_s&.first(10_000),
        url: params[:url].presence,
        source: pushed_source
      }
    end

    def pushed_source = params[:source].to_s.in?(PUSHED_SOURCES) ? params[:source].to_s : "claude"
  end
end
