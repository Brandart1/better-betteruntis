# Decisions made while the maintainer was away ("savestate")

Each entry: what I chose, the alternative, and how to switch. Delete entries
once confirmed.

## 1. Version swap: server = 0.5.0, teacher = 0.6.0
- **Chosen:** swapped (agreed in chat before leaving). Teacher branch commit
  `6a2f037` (0.6.0+66) renamed its docs to 0.6.0; this branch uses 0.5.0+N.
- **Alternative:** keep teacher = 0.5.0, server = 0.6.0.
- **Undo:** nothing was released under the new numbers. Change `version:`
  in `pubspec.yaml` on both branches (keep +N increasing), revert the
  "0.6.0 alphas" wording in teacher's docs/API.md, docs/FEATURES.md and
  docs/TEACHER_FEATURES.md, and rename release notes files if any.
