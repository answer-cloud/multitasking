---
name: done-assign
description: Put a task on a list in Done, the team's task app — a teammate's or the user's own. Use when the user says "assign Sam …", "give Alex a task", "put this on Jo's list", "add a task for Sam", "remind Alex to …", or "add that to my list".
---

# Assigning a task in Done

Run the hook the user installed from Done's "Connect agents" page:

```bash
~/.config/multitasking/agent-hook assign "<person>" "<task>" [--project "<project>"] [--notes "<notes>"]
```

- `<person>` is a teammate's first name, full name or email, as the user said
  it. Use `me` for the user's own list.
- `<task>` is one line saying what needs doing, written so it makes sense to
  somebody who was not in this conversation. Start with a verb.
- `--project` files it under one of the team's projects, by name. Leave it out
  unless the user named one or the work is plainly about the repository you
  are in — then pass that repository's name.
- `--notes` carries anything the person will need: a link, a file path, the
  decision behind the task. Leave it out if the title says it all.

Several tasks are several commands, one each.

The command prints whose list the task landed on. Tell the user that, in a
few words. If it fails it prints why and exits non-zero. When it says nobody
is called that, it lists who is on the team: ask the user which of them they
meant rather than guessing.

If the hook is missing, tell the user to install it from the "Connect agents"
page in Done.
