# Command line

This document gives the command line of earshot. The requirements are R-CT-1 to R-CT-4 in `docs/REQUIREMENTS.md`. The decision is D-15 in `docs/DECISIONS.md`.

## 1. What it is

The app program is also the command line. If the first word is a control word, the program runs one command and stops. No window opens.

The control words are `settings`, `plugins`, `run`, `status`, `reload` and `help`.

The program is in the app bundle:

```sh
EARSHOT=~/projects/earshot-t0/app/build/Earshot.app/Contents/MacOS/earshot
"$EARSHOT" help
```

## 2. Commands

| Command | What it does |
|---|---|
| `settings` | Lists each setting and its value. |
| `settings get <name>` | Shows one setting. |
| `settings set <name> <value>` | Changes one setting. The running app uses the change at once. |
| `settings reset <name>` | Sets one setting back to its default. |
| `plugins` | Lists the plugins, with the approval state and the problems. |
| `plugins reload` | Reads the plugins folder and the approvals again. This is the same as "Read again" in the Plugins tab. |
| `plugins restart <id>` | Stops one plugin and starts it again. |
| `run <words>` | Routes the typed words as the Test tab does. It does no action. |
| `run <words> --actions` | Routes the words and does the action, as "Run actions" in the Test tab. |
| `run <words> --actions --wait <s>` | Also waits up to `<s>` seconds for the plugin answers. The default is 3 s. The maximum is 20 s. |
| `status` | Shows the version, the commit, the mode, the state and the running plugins. |
| `reload` | Makes the running app read `settings.json` and the plugins folder again. |

Examples:

```sh
"$EARSHOT" settings set mode alwaysOn
"$EARSHOT" settings set wakePhrase hey atlas
"$EARSHOT" settings set playSounds off
"$EARSHOT" plugins restart pa
"$EARSHOT" run "todo buy milk" --actions
```

## 3. Values

- A true or false setting takes `true`, `false`, `on`, `off`, `yes`, `no`, `1` or `0`.
- A number setting takes a number.
- `mode` takes `hold` or `alwaysOn`. `engine` takes `auto`, `apple` or `parakeet`. `tier2` takes `off` or `jev`.
- Other settings take the words after the name.

If the settings cannot take a value, the command shows an error and does not change the file.

If earshot does not run, `settings set` and `settings reset` still change `settings.json`. earshot reads the file at its next start.

## 4. Safety rules

- The command line cannot approve a plugin or remove an approval. The owner does this in Manage > Plugins (R-PL-4).
- `tier2` and `jevSeesScreen` send data to the cloud (R-MD-1). To turn one on, add `--owner-ok`. Use this flag only when the owner said so. To turn one off, no flag is necessary.
- `run` without `--actions` is a dry run.
- `run --actions` does the same actions as a spoken command, with the same rules. earshot never presses Send without the word "send" (R-NV-5).
- `run --actions` needs the Accessibility permission for the program that starts the command, for example Terminal. Thus the command line does not give the earshot permission to a program that does not have it (R-CT-3).
- The command line talks to the app through the socket file `control.sock` in the store folder. The file mode is 0600. The app checks that the peer has the same user id. For `run --actions`, the app also checks that the peer has the code signature of earshot.
- The command line never opens a network port (R-CT-2).

## 5. Exit codes

| Code | Meaning |
|---|---|
| 0 | The command worked. |
| 1 | The command failed, or the app did not answer. The error is on standard error. |
