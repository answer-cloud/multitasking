# frozen_string_literal: true

module Tasks
  # Handing a task to Claude or Codex: notes who has it, then sends the browser
  # to the agent's app with the task typed into a new session. See
  # Task#agent_link.
  #
  # The form posts without Turbo. The answer is a redirect to a claude:// or
  # codex:// link, which a fetch cannot follow and a browser hands straight to
  # the app, leaving the page where it was. The open dashboard hears about the
  # change the way it hears about agent pings: a broadcast.
  class HandoffsController < ApplicationController
    before_action :set_task

    def create
      authorize @task, :update?
      # Taken from the list, not the request: this redirect leaves the app,
      # so nothing a request says may end up in it.
      agent = Task::AGENTS.detect { |name| name == params[:agent] }
      return head :unprocessable_content if agent.nil?

      @task.hand_to!(agent)
      broadcast

      redirect_to @task.agent_link(agent), allow_other_host: true, status: :see_other
    end

    private

    def set_task
      @task = current_team.tasks.find(params[:task_id])
    end

    def broadcast
      Turbo::StreamsChannel.broadcast_replace_to(current_team, :tasks, target: @task, partial: "tasks/task",
                                                                       locals: { task: @task, projects: current_team.projects.alphabetical.to_a })
    end
  end
end
