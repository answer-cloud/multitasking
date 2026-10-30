# frozen_string_literal: true

module ConnectionsHelper
  # The save-this-tab bookmarklet. It opens TasksController#new in a new tab
  # with the page's title and address, and the person saves it from there.
  #
  # It sends nothing itself: the form on our side carries the CSRF token and
  # the sign-in, so the bookmarklet needs no inbox token and a page it runs on
  # learns nothing about us. `noopener` stops our page reaching back into theirs.
  def tab_bookmarklet
    "javascript:(()=>{window.open(#{new_task_url.to_json}+'?'+new URLSearchParams(" \
      "{title:document.title,url:location.href}),'_blank','noopener')})()"
  end
end
