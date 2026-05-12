---
name: merge-upstream
description: Sync upstream into this fork. Use when the user asks to "merge upstream", "pull upstream", "sync upstream", or "/merge-upstream". This repo has two branches — `main` mirrors `upstream/main` exactly (never edit it directly), and `custom` carries local patches. The skill fast-forwards `main` from `upstream`, merges into `custom`, resolves conflicts favoring custom's intentional changes, runs tests, and pushes only with explicit permission.
---

# merge-upstream

## Branch layout (this repo)

- Remote `upstream` — read-only mirror of `Enough-Software/enough_mail`.
- Remote `origin` — our fork (`quire-io/enough_mail`).
- Branch `main` — tracks `upstream/main` exactly. Never edit directly; it only moves via fast-forward.
- Branch `custom` — branched from `main`; carries Quire's local patches.

## Procedure

### 1. Preflight

```bash
git status
git remote -v
```

Working tree must be clean. Confirm both `upstream` and `origin` remotes exist. If not, stop and ask.

### 2. Fetch and report

```bash
git fetch upstream
git fetch origin
git log --oneline main..upstream/main          # new upstream commits
git log --oneline upstream/main..main          # local-only on main — must be empty
git log --oneline --no-merges main..custom     # custom-only commits to preserve through the merge
```

Show the user a brief summary: how many new upstream commits, and the list of custom-only commits.

If `upstream/main..main` is non-empty, `main` has drifted — stop and ask the user. Policy: `main` is never edited directly.

If `main..upstream/main` is empty, there is nothing to merge — tell the user and stop.

### 3. Fast-forward `main`

```bash
git checkout main
git merge --ff-only upstream/main
```

If fast-forward fails, the mirror has diverged — stop and ask.

### 4. Merge `main` into `custom`

```bash
git checkout custom
git merge main
```

If clean, jump to step 6.

### 5. Resolve conflicts

For each conflicted file:

- Show the conflict (`git diff <file>`).
- Form a proposed resolution. **Default bias: keep custom's intentional changes**, because `main` is just a mirror — anything that conflicts represents a deliberate local patch.
- Cross-reference custom-only commits (from step 2) to explain *why* a hunk is in custom — cite the commit subject (e.g. "Fix #21337", "switched print → logger.warning"). This makes each resolution auditable.
- Adopt upstream's purely-cosmetic reformatting around the kept logic when clearly unrelated to the patched behavior.
- Identify obsolete patches: if a custom commit appears already addressed upstream (e.g. SDK constraint bumped past ours, equivalent fix landed), call it out and ask whether to drop it.

Present the list as a table. **Wait for explicit confirmation** before applying — never auto-resolve.

After applying, verify:

```bash
rg -n '^(<<<<<<<|=======$|>>>>>>>)' .       # must return nothing
git diff --name-only --diff-filter=U        # must be empty
git add <resolved files>
```

### 6. Verify

```bash
dart pub get
dart test
dart analyze
```

Also sanity-check that each custom patch survived the merge — grep for distinctive markers (regex, function name, identifier) drawn from each custom-only commit, e.g.:

```bash
rg -n "replaceAll\(RegExp" lib/src/codecs/base64_mail_codec.dart   # Fix #21337
rg -n "repairBase64"        lib/src/codecs/base64_mail_codec.dart   # Fix #20208
rg -n "_logger\.warning"    lib/src/codecs/                         # logger swap
rg -n "late List<int> password" lib/src/private/smtp/commands/smtp_auth_cram_md5_command.dart
rg -n "codec = encodingUtf8" lib/src/codecs/mail_codec.dart
rg -n 'event_bus|EventBus'   lib/                                   # must be empty (dropped upstream)
```

Pre-existing lints in custom's `import "package:logging/logging.dart"` lines (prefer_single_quotes, directives_ordering, lines_longer_than_80_chars) are expected and not introduced by the merge.

If tests fail, stop and report. Do not commit broken code.

### 7. Review surviving customizations

For each custom-only commit, classify:

- **Still needed** — upstream has no equivalent; the patch carries weight.
- **Obsolete but harmless** — superseded by upstream (e.g. SDK bump) but doesn't break anything; safe to leave alone or revert in a follow-up.
- **Obsolete and harmful** — actively conflicts with new upstream behavior; flag for removal.

Present this table to the user.

### 8. Commit and push (only with explicit permission)

When the user says yes:

```bash
git commit -m "$(cat <<'EOF'
Merge branch 'main' into custom

Co-author: Claude <model>
EOF
)"
git push origin main
git push origin custom
```

Replace `<model>` with the actual model name (e.g., `Opus 4.7 (1M context)`, `Sonnet 4.6`).

## Safety rules

- **Never push --force** to either branch.
- **Never auto-resolve conflicts.** The user must confirm the resolution plan.
- **Never commit without explicit permission.** Even after conflicts are resolved, pause before `git commit`.
- **Never edit `main` directly.** It only moves via fast-forward from `upstream/main`.
- If the working tree is dirty at the start, stop and ask.

## Recovery

- `git merge --abort` cleanly restores pre-merge state. Prefer this.
- **Avoid** `git stash` + `git checkout HEAD -- .` mid-merge — that wipes `MERGE_HEAD` and discards conflict markers, making the merge state unrecoverable as a merge commit. If it happens, the stashed content can still be salvaged: `git show stash@{0}:<file>` inspects it, `git checkout stash@{0} -- <file>` restores a file from the stash. You then have to redo the merge (`git merge main` again) and use the stash content to re-apply resolutions.
