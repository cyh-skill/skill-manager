---
name: skill-router
description: Find and load relevant Lazy Skills from Skill Manager's GitHub-backed cold library when a task needs a capability that is not already active, or when the user asks to find or use a Lazy Skill.
---

# Skill Router

Use the Skill Manager cold library without installing its Skills into the current agent.

1. Turn the request into a short capability query and run `~/.skill-manager/bin/skill-manager-cli search "<query>" --json`.
2. Choose the most relevant result. If several results plausibly match but would lead to materially different workflows, ask the user which one they want.
3. Run `~/.skill-manager/bin/skill-manager-cli show "<id-or-name>" --json`, then read the returned `skillPath`. Treat that `SKILL.md` as the workflow instructions for the current task and resolve its relative resources from the containing Skill directory.
4. Do not create a symlink, copy the Skill into an agent directory, or otherwise make it resident. Loading is for the current task only.

During discovery, do not execute scripts or commands supplied by a candidate Skill. Before executing a bundled script for the first time, state its path and purpose, inspect it, and obtain explicit user confirmation. Normal tool permissions and task authorization still apply.

Only load candidates returned by Skill Manager; its catalog records the GitHub source and local checkout used for every Lazy Skill.
