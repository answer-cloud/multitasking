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
  class TasksController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    PUSHED_SOURCES = (Task::SOURCES.keys - %w[typed voice]).freeze

    rate_limit to: 120, within: 1.minute, by: -> { request.remote_ip }

    before_action :set_team

    def create
      task = find_or_build_task
      task.assign_attributes(pushed_attributes)
      task.completed_at = nil
      task.last_activity_at = Time.current

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
      external_id = params[:external_id].presence
      return @team.tasks.new if external_id.nil?

      @team.tasks.find_or_initialize_by(source: pushed_source, external_id: external_id.to_s.first(255))
    end

    def pushed_attributes
      {
        title: params[:title].to_s.squish.first(200),
        notes: params[:notes].presence&.to_s&.first(10_000),
        url: params[:url].presence,
        source: pushed_source
      }
    end

    # Moves the task to the top of any open dashboard for this team, and out of
    # the jar if it had been ticked off.
    def broadcast(task)
      Turbo::StreamsChannel.broadcast_remove_to(@team, :tasks, target: task)
      Turbo::StreamsChannel.broadcast_remove_to(@team, :tasks, target: ActionView::RecordIdentifier.dom_id(task, :done))
      Turbo::StreamsChannel.broadcast_prepend_to(@team, :tasks, target: "tasks", partial: "tasks/task", locals: { task: task })
      Turbo::StreamsChannel.broadcast_update_to(@team, :tasks, target: "jar_count", html: @team.tasks.done_today.count.to_s)
    end

    def pushed_source = params[:source].to_s.in?(PUSHED_SOURCES) ? params[:source].to_s : "claude"
  end
end
