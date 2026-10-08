---
name: xcode-cloud
description: Plan and trigger dev or staging Xcode Cloud builds by pushing a versioned Git tag. Use for requests to start a TestFlight build; bare release tags follow the separate release workflow.
---

# Xcode Cloud builds

This project starts Xcode Cloud builds from pushed Git tags. Use `scripts/xcode_cloud_tag.sh` for dev and staging tags. The supported app project is `グルメップ.xcodeproj`; its `MARKETING_VERSION` supplies the tag version. The repository also contains a separate `ごはん日和.xcodeproj`, which is not the release target.

| Tag | Intended build |
| --- | --- |
| `dev.<version>-<label>` | Verification build |
| `staging.<version>-<label>` | Production configuration build |
| `<version>` | Release build; use the separate release workflow, never this skill |

## Trigger a dev or staging build

1. Infer `staging` for requests mentioning production, staging, or pre-release verification. Use `dev` for other verification builds. If the kind is ambiguous, ask which one.
2. If no label is supplied, infer a short English kebab-case label from the current branch or recent commit. A supplied complete tag must match the selected kind and current `MARKETING_VERSION`.
3. Run `bash scripts/xcode_cloud_tag.sh plan <dev|staging> <label-or-complete-tag>`. The command requires a clean working tree, checks local and `origin` tag collisions, and prints the exact tag and commit SHA without changing Git state.
4. Show the user the tag and full commit SHA from the plan. Explain that pushing it starts an Xcode Cloud build and delivery to TestFlight; for staging, state that it is the production configuration build. Wait for the user's explicit confirmation before creating or pushing the tag.
5. After confirmation, run `bash scripts/xcode_cloud_tag.sh create <complete-tag> <planned-commit-sha>`. This verifies that `HEAD` is still the planned commit, creates an annotated tag, and pushes only that tag. It retries a failed push after 2, 4, 8, and 16 seconds. If the push still fails, report that the local tag remains and do not delete it automatically.
6. Report the tag, commit SHA, and whether the tag was pushed. Say that Xcode Cloud should start only after a successful push; do not claim a build completed without checking its status.

## Xcode Cloud setup

The Xcode Cloud workflow in App Store Connect must be configured to start on Git tag changes and distribute successful archives to TestFlight. Include the `グルメップ` scheme and the repository's `ci_scripts` when configuring it. If dev and staging require different build settings, configure matching tag conditions and settings in Xcode Cloud; the tag script does not change build settings. The app currently has no dev/staging API endpoint setting, so the tag alone does not switch a backend environment. The setup is external to this repository and is not changed by the tag commands.

`ci_scripts/ci_post_xcodebuild.sh` writes the triggering `CI_TAG` to `TestFlight/WhatToTest.ja.txt` after a successful TestFlight archive. Xcode Cloud uses this file for the TestFlight “What to test” field. Dev and staging builds therefore show the complete tag as their tester note.

Do not use this flow for a bare version tag or invoke `make create_release_tag`; those belong to the project's release workflow.
