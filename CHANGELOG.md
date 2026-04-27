# Changelog

All notable changes to remote-launcher will be documented here.

## [Unreleased]

### Added
- Initial release.
- `bin/ssh-shell` — `CLAUDE_CODE_SHELL` wrapper, forwards Bash to remote via SSH ControlMaster, tracks remote cwd between calls.
- `bin/remote-launcher` — launcher CLI: tests SSH, sets env, exec's Claude with system-prompt addendum.
- `bin/remote-launcher-doctor` — diagnostic.
- `prompts/REMOTE_PROMPT.md` — appended to Claude system prompt; explains Bash→VM, Read/Edit/Write→Mac, heredoc for VM files.
- `skill/SKILL.md` — Claude Code skill manifest.
- Test harness using Apple's `container` (`tests/`).
- `install.sh` / `uninstall.sh`.
- Documentation: architecture, security model, troubleshooting.
