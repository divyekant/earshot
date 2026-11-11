# Plugins

This document gives the plugin contract of earshot, version 1. The contract is experimental until a second plugin exists. The requirements are R-PL-1 to R-PL-5 in `docs/REQUIREMENTS.md`. The decision is D-14 in `docs/DECISIONS.md`.

## 1. What a plugin is

A plugin is a separate program on the Mac. earshot starts it and sends text to it. The plugin sends back data: answers and targets.

- No plugin code runs inside earshot (R-PL-1).
- A plugin gets only the words after its lead words, and only the context that its manifest names. A plugin never gets audio (R-PL-2).
- A plugin answer is text on screen. It is never a command. A plugin cannot make earshot click, type or send (R-PL-3).
- The owner approves each plugin. A core command wins over a plugin lead (R-PL-4).
- A plugin cannot slow a command. earshot shows its note at once and does not wait for the plugin (R-PL-5).

A plugin does not add a verb or an intent to earshot. All plugins use one intent, `handOff` (`docs/DESIGN.md`, section 3.0).

## 2. Install a plugin

1. Open the Manage window of earshot.
2. Open the Plugins tab.
3. Click "Open the plugins folder".
4. Put the plugin in its own folder in the plugins folder. The folder name must be the plugin id.
5. Click "Read again".
6. Read the lead words, the context and the network line of the plugin.
7. Turn on "Approved".

The plugins folder is `~/Library/Application Support/earshot/plugins/`. Each plugin is in `plugins/<id>/`, with its `plugin.json` file.

If the `plugin.json` file changes, the approval stops. Approve the plugin again.

## 3. The manifest: plugin.json

```json
{
  "contract": 1,
  "id": "echo",
  "name": "Echo",
  "version": "0.1.0",
  "leads": ["say back"],
  "context": ["app"],
  "run": ["./plugin.sh"],
  "network": []
}
```

| Key | Required | Meaning |
|---|---|---|
| `contract` | Yes | The contract version. earshot loads only version 1. |
| `id` | Yes | Lower-case letters, digits and `-`. The same as the folder name. |
| `name` | No | The name on screen. The default is the id. |
| `version` | No | The version of the plugin. |
| `leads` | Yes | The words that start a command for the plugin. 1 to 5 words each. |
| `context` | No | The context for each command: `app` (the bundle id of the front app), `windowTitle`, `url`. The default is none. |
| `run` | Yes | The program and its arguments. A relative path starts at the plugin folder. |
| `network` | No | The network hosts that the plugin says it uses. The default is none. earshot shows it in the Plugins tab. earshot does not enforce it. |

### 3.1 Rules for lead words

earshot does not use a lead in these conditions. The Plugins tab shows the reason.

- The first word starts a core command, for example "open", "type", "click", "send", "find", "show", "scroll", "back", "undo", "stop", "yes" or "no".
- The first word is a filler word, for example "please", "can", "to" or "the".
- The lead starts with the name of an app in the app table.
- The lead has more than 5 words.

If two plugins have the same lead, the plugin with the first id (in alphabetical order) gets it.

## 4. How earshot routes a plugin command

1. The router reads the start of the command. It removes filler words such as "hey" and "can you".
2. If the command starts with a lead, the router makes the intent `handOff`. The longest lead wins. The match ignores spaces and hyphens between words, so the lead "todo" also matches "to do" and "to-do".
3. The words after the lead are text. earshot does not read commands in them. "remind me to open Slack" sends "open Slack" to the plugin. Slack does not open.
4. earshot sends the text to the plugin and shows a note at once, for example "→ Echo · say back".
5. The plugin answers later. earshot shows the answer as a note.

Some more rules:

- The rule is in tier 0 of the router. The router is sure, so tier 2 (Jev) never runs for a plugin command. The words after a lead never go to Jev (R-MD-1, D-9).
- A plugin command is never a chain of commands. A trailing "and send" is text for the plugin. earshot does not send.
- With the hold key, a sentence that starts with a lead goes to the plugin. It does not go into the focused text box.
- After a bare "type", the next sentence is dictation (R-NV-4). A lead in it is text, and earshot types it.
- In always-on mode, the wake phrase and the voice check apply as for each other command.
- The Test tab routes typed commands to plugins.
- On a sign-in, code or payment page, earshot sends no context. The plugin gets the text only.

The activity log keeps the lead and the number of words. It does not keep the words.

## 5. The connection

earshot starts the program with posix_spawn. The program reads JSON lines from stdin and writes JSON lines to stdout. Each message is one JSON object on one line. No network port is open.

- earshot makes macOS treat the program as a separate process for the privacy permissions. The program does not get the Microphone or the Accessibility permission of earshot.
  - Test on the Mac, 2026-11-11, builds 2e53860 and abc46df: a test plugin ran `AXIsProcessTrusted` through osascript. The result was `false` in the plugin, and `true` in a shell with the Accessibility permission. The plugin was a child process of earshot.
  - A plugin that needs a permission, for example Reminders, must get its own permission from macOS. This is not tested yet. A command-line program can need an embedded Info.plist or a helper app before macOS shows the permission question.
- The program gets only these environment variables: `EARSHOT_PLUGIN_DATA` (a data folder for the plugin), `EARSHOT_CONTRACT` (`1`), `PATH`, `HOME`, `LANG` and `TMPDIR`.
- The data folder is `~/Library/Application Support/earshot/plugin-data/<id>/`. An update of the plugin does not change this folder.
- stderr goes to `/dev/null`.
- earshot starts each approved plugin when earshot starts. The plugin runs while earshot runs.
- If the plugin stops, earshot starts it again after 2 s. After 3 starts in 60 s, the plugin stays off until the next change in the Plugins tab, or the next start of earshot.
- When earshot quits, stdin of the plugin closes. The plugin must stop when stdin closes.
- earshot drops a line that is longer than 64 KB, and a line that is not a message.

### 5.1 From earshot to the plugin

`hello`: the first message.

```json
{"type":"hello","contract":1}
```

`command`: one command.

```json
{"type":"command","id":"8C1F…","lead":"say back","text":"the blue fox","context":{"app":"com.apple.Notes"}}
```

The text can be empty, for example for a lead such as "what is due".

### 5.2 From the plugin to earshot

`answer`: a note on screen.

```json
{"type":"answer","re":"8C1F…","kind":"note","text":"3 words"}
{"type":"answer","kind":"list","text":"Due today","items":["Pay the rent","Call the plumber"]}
{"type":"answer","kind":"alert","text":"Time to stretch"}
```

| Key | Meaning |
|---|---|
| `re` | The id of the command. Leave it out for an alert at a time that the plugin chose. |
| `kind` | `note`, `list` or `alert`. |
| `text` | The text. |
| `items` | The lines of a list. earshot shows the first 10, with numbers. |

- earshot shows an answer for 6 s. It cuts the text at 500 characters.
- An `alert` also plays a sound, if "Play sounds" is on. It also goes to the macOS Notification Center. The first alert asks for the Notifications permission.
- earshot shows an answer only as text. It never runs an answer as a command.

`targets`: the names that the plugin knows, for example to-dos, projects and documents.

```json
{"type":"targets","targets":[{"id":"t1","name":"the lease","kind":"document","open":"/Users/me/Documents/lease.pdf"}]}
```

Each `targets` message replaces the list from before. `open` is an absolute file path or an http or https address. A target with no `open` value is kept, but "open" does not use it.

#### 5.2.1 "open <target>"

The core verb "open" opens a target, for example "open today" or "open the lease". The plugin does not run the action. earshot opens the target itself.

- The words after "open", "go to" or "switch to" must be the whole name. The match ignores spaces and hyphens. earshot ignores a leading "the" or "my", and a trailing "page", "list" or "project".
- An app name wins. If a plugin has a target "Notes", "open Notes" opens the app Notes.
- A target comes before the names of chats and the labels on the screen.
- If two plugins have a target with the same name, the plugin with the first id gets it.
- earshot opens a web address in the browser, a document in its app, and a folder in Finder.
- The document types are `html`, `htm`, `pdf`, `txt`, `md`, `markdown`, `rtf`, `csv`, `png`, `jpg`, `jpeg`, `gif`, `heic` and `webp`.
- earshot never opens a program, a script, an installer or a package (a folder with a type, such as an app). It refuses other address types, such as `file:` and `ftp:`. It follows a link to its file before it checks the type.

earshot drops a message of an unknown type. So a newer plugin can talk to an older earshot.

## 6. The example plugin

`app/examples/plugins/echo/` is a small plugin in shell. It answers each command with the number of its words. To try it:

1. Copy the folder `echo` into the plugins folder.
2. In the Plugins tab, click "Read again", and approve "Echo".
3. Hold the key and say "say back the blue fox".
4. The note shows "Echo: 3 words".

## 7. Not in version 1

- More context keys, for example the selected text or the file of the front window.
- "undo that" for the last plugin answer.
