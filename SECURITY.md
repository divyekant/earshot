# Security policy

## Supported versions

earshot is early software. Only the latest commit on `main` gets security fixes.

## Report a vulnerability

Do not open a public issue for a security problem.

1. Go to the [Security tab](https://github.com/divyekant/earshot/security) of the repository.
2. Click **Report a vulnerability**.
3. Describe the problem, the steps to reproduce it, and its effect.

You get a first reply in 7 days or less.

## Scope

These problems are in scope:

- earshot presses Send, or does another action that cannot be undone, without an explicit "send" command from the owner (R-NV-5, R-ON-5).
- earshot acts in an app that the owner did not approve.
- earshot acts on a sign-in, code or payment page.
- Audio, a screenshot or message text leaves the Mac.
- The Jev key leaves the Keychain, or shows in a log or a settings file.
- In always-on mode, speech from another person or from a video starts an action.

These problems are out of scope:

- A problem that needs an attacker who already controls the Mac or the user account.
- A problem in macOS, in an Apple framework, or in a third-party app.
