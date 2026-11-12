# Who can change the repository

The repository is [bakermarcos/volta](https://github.com/bakermarcos/volta). The default branch is `master`.

## Master

Anyone can open a pull request. Only the **bakermarcos** account can merge into `master`.

The pull request needs a review from `@bakermarcos`, who owns everything in `.github/CODEOWNERS`. Until that review exists, the merge stays blocked. Another account, even with write permission, cannot finish the merge. The rule **Master: só o dono faz merge** lets only the owner update `master`, and only through a pull request. Direct push and force push to `master` are refused.

Accepting means approving the pull request and then merging it. Both actions belong to the same account.

## Branches created by the owner

Every branch outside `contrib/` can be created, updated, or deleted only by authorized people. Today the authorized person is **bakermarcos**. Force push on those branches is limited to the same list.

To authorize someone else on one of those branches, without giving them the `master` merge:

1. Open the repository rules in Settings → Rules → Rulesets.
2. In the rule **Branches do dono: só pessoas autorizadas**, add the account under Bypass.
3. Leave the mode on **Always**. Do not add that account to the `master` rule.

## Other people's branches

A collaborator opens the branch with the `contrib/` prefix, for example `contrib/ajuste-hud`. That prefix is outside the lock on the owner's branches, so the author pushes its commits. The pull request is still under the `master` rule: it lands only after acceptance, and only the owner merges.

Someone who is not a collaborator opens the pull request from a fork. They do not need a `contrib/` branch.

## Repository security

The code is public. The game room is not. It exists only on the home network, and the TV's address does not go in the repository.

Secret scanning, push protection for secrets, vulnerable-dependency alerts, and private vulnerability reports are already on in GitHub.

`.github/dependabot.yml` asks for a weekly Dart and Flutter update. It takes effect once that file is on `master`.

Report a flaw in private, by the path in [SECURITY.md](../SECURITY.md). Do not open a public issue with an IP, a room code, or a certificate.
