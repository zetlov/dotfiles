# Tooling

## Runtime Versions (mise)

Runtime versions (node, python, ruby, etc.) are managed by **mise**.

- **Execute through mise**: Do not assume a globally installed runtime. mise is
  activated in interactive shells via `eval "$(mise activate zsh)"`, but
  non-interactive/agent shells may not source `.zshrc`. If a tool or version is
  missing or looks wrong, run it through `mise exec -- <cmd>` (or `mise x -- <cmd>`).
- **Pin versions with mise**: Pin project tool versions in `mise.toml` (or
  `.tool-versions`). Never install runtimes globally; add them with
  `mise use <tool>@<version>`.
- **Tasks via `mise run`**: Define repeated project commands as mise tasks and run
  them with `mise run <task>` instead of ad-hoc scripts.
