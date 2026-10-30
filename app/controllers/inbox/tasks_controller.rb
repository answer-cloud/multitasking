# frozen_string_literal: true

module Inbox
  # Where other tools push tasks in: Claude Code and Codex hooks today, and the
  # Chrome extension, Slack and email later.
  #
  # There is no user here. The caller proves which team it writes to with the
  # team's inbox token, sent as a bearer token — never in the URL, where it
  # would end up in server logs and browser history.
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

    before_action :set_team

    def create
      task = find_or_build_task
      task.assign_attributes(pushed_attributes)
      task.completed_at = nil
      task.last_activity_at = Time.current
      task.put_on_top if task.persisted?
      task.project ||= @team.projects.claim_directory(params[:directory])

      if task.save
        broadcast(task)
        render json: { id: task.id, created: task.previously_new_record? },
               status: task.previously_new_record? ? :created : :ok
      else
        render json: { errors: task.errors.full_messages }, status: :unprocessable_content
      end
    end

    private

    def set_team
      @team = authenticate_with_http_token { |token, _| Team.find_by(inbox_token: token) if token.present? }

      head :unauthorized if @team.nil?
    end

    # Started from the team, like every other tenant query.
    def find_or_build_task
      external_id = params[:external_id].presence&.to_s&.first(255)
      return @team.tasks.new if external_id.nil?

      task = @team.tasks.find_by(source: pushed_source, external_id: external_id) || handed_off_task || @team.tasks.new
      task.external_id = external_id
      task
    end

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

    # Moves the task to the top of any open dashboard for this team, and out of
    # the jar if it had been ticked off. A priority task stays in the priority
    # list.
    def broadcast(task)
      list = ApplicationController.helpers.task_list_id(task)

      Turbo::StreamsChannel.broadcast_remove_to(@team, :tasks, target: task)
      Turbo::StreamsChannel.broadcast_remove_to(@team, :tasks, target: ActionView::RecordIdentifier.dom_id(task, :done))
      Turbo::StreamsChannel.broadcast_prepend_to(@team, :tasks, target: list, partial: "tasks/task",
                                                                locals: { task: task, projects: @team.projects.alphabetical.to_a })
      Turbo::StreamsChannel.broadcast_update_to(@team, :tasks, targets: "[data-done-count]", html: @team.tasks.done_today.count.to_s)
    end

    def pushed_source = params[:source].to_s.in?(PUSHED_SOURCES) ? params[:source].to_s : "claude"
  end
end
