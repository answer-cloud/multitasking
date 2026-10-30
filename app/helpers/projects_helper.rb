# frozen_string_literal: true

module ProjectsHelper
  # A project's folder as you would type it: "~/code/app" rather than
  # "/Users/you/code/app". Display only — the full path is what matching uses,
  # and it stays in the title for anyone who needs it.
  def short_directory(project)
    return "No folder" if project.directory.nil?

    short = project.directory.sub(%r{\A/(?:Users|home)/[^/]+(?=/|\z)}, "~")
    tag.span(short, title: project.directory)
  end

  # A project's name that goes back to where its work last happened: the same
  # place its latest linked task's "Open" button goes. Plain text when none of
  # its tasks has a link, and for Other.
  def project_link(project, **options)
    if (task = project&.latest_linked_task)
      open_link(task, project.name, css: options.delete(:class), title: "Back to: #{task.title.truncate(80)}", **options)
    else
      tag.span(project_name(project), **options)
    end
  end

  # A project's name behind a dot of its colour. Other has no colour, so its
  # dot stays blank. The colours are in components/_project_tag.scss.
  def project_tag(project, **options)
    css = [ "project-tag", ("project-tag--#{project.color}" if project), options.delete(:class) ]
    project_link(project, class: css, **options)
  end
end
