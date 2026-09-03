---
name: skill-router
description: Find and load relevant Lazy Skills from Skill Manager's GitHub-backed cold library when a task needs a capability that is not already active, or when the user asks to find or use a Lazy Skill.
---

# Skill Router

Use the Skill Manager cold library in place for the current task. The selected Skill remains in the cold library rather than being installed into the current agent.

1. Turn the request into a short capability query and run `~/.skill-manager/bin/skill-manager-cli search "<query>" --json`.
2. Choose the most relevant result. If several results plausibly match but would lead to materially different workflows, ask the user which one they want.
3. Run `~/.skill-manager/bin/skill-manager-cli show "<id-or-name>" --json`, then read the returned `skillPath`. Treat that `SKILL.md` as the workflow instructions for the current task and resolve its relative resources from the containing Skill directory.
4. Load the returned `SKILL.md` in place for the current task and leave the cold-library checkout and agent Skill directories unchanged.

Discovery reads only catalog metadata and candidate instructions. Before the first execution of a bundled script, state its path and purpose, inspect it, and obtain explicit user confirmation. Normal tool permissions and task authorization still apply.

Only load candidates returned by Skill Manager; its catalog records the GitHub source and local checkout used for every Lazy Skill.
