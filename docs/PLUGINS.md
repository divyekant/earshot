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

If you install a new build of the plugin program, click "Read again". earshot stops the old program and starts the new one. The approval stays. earshot sees a change in the program file and in each file directly in the plugin folder.

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
| `context` | No | The context for each command: `app` (the bundle id of the front app), `windowTitle`, `url`, `document`, `selection`. The default is none. See section 5.1. |
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
  - A plugin that needs a permission, for example Reminders, must get its own permission from macOS.
  - Test on the Mac, 2026-11-11, PA plugin at commit e8e87cf: earshot started the PA (`EarshotPA.app/Contents/MacOS/earshot-pa`) as a plugin. The PA asked for full access to Reminders. macOS gave the access to the PA 3 s after its start. The program has an `Info.plist` in its app bundle and in the linker section `__TEXT,__info_plist`, and a stable code signature. Use the same layout for a plugin that needs a permission.
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

The context keys:

| Key | Value |
|---|---|
| `app` | The bundle id of the front app. |
| `windowTitle` | The title of the front window. |
| `url` | The address of the page in the front window. |
| `document` | The file path of the document in the front window (the `AXDocument` attribute). A Finder window gives no `AXDocument`. For it, earshot reads the file addresses (`AXURL`) of the items in the window and gives the folder whose name is the window title. |
| `selection` | The selected text of the focused element (`AXSelectedText`), cut at 2,000 characters. Never the text of a password field. |
| `pageText` | The text of the web page in the front window. It does not come with the command. The plugin asks for it after the command. See section 5.3. |

- earshot sends only the keys that the manifest names. A key with no value is absent.
- earshot reads `document` and `selection` only for a plugin that names them. The read comes before the command goes to the plugin. The note does not wait for the plugin.
- On a sign-in, code or payment page, earshot sends no context.
- The Plugins tab shows each key in words. It shows `selection` and `pageText` in orange: the plugin gets the text that you selected or the text of the page, and can keep it.
- The activity log keeps no context value.

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

Each `targets` message replaces the list from before. `open` is an absolute file path, an http or https address, or a `message://` address of one mail. A target with no `open` value is kept, but "open" does not use it.

#### 5.2.1 "open <target>"

The core verb "open" opens a target, for example "open today" or "open the lease". The plugin does not run the action. earshot opens the target itself.

- The words after "open", "go to" or "switch to" must be the whole name. The match ignores spaces and hyphens. earshot ignores a leading "the" or "my", and a trailing "page", "list" or "project".
- An app name wins. If a plugin has a target "Notes", "open Notes" opens the app Notes.
- A target comes before the names of chats and the labels on the screen.
- If two plugins have a target with the same name, the plugin with the first id gets it.
- earshot opens a web address in the browser, a `message://` address in Mail (it shows one mail and sends nothing), a document in its app, and a folder in Finder.
- The document types are `html`, `htm`, `pdf`, `txt`, `md`, `markdown`, `rtf`, `csv`, `png`, `jpg`, `jpeg`, `gif`, `heic` and `webp`.
- earshot never opens a program, a script, an installer or a package (a folder with a type, such as an app). It refuses other address types, such as `file:` and `ftp:`. It follows a link to its file before it checks the type.

earshot drops a message of an unknown type. So a newer plugin can talk to an older earshot.

### 5.3 Page text

A plugin whose manifest names `pageText` can ask for the text of the web page in the front window, once for each command. The read is not on the command path: the command note does not wait for it (R-PL-5).

1. earshot sends the `command`.
2. The plugin sends the ask, with the id of the command, in 10 s or less:

   ```json
   {"type":"pageText","re":"8C1F…"}
   ```

3. earshot shows the note "→ <plugin name> · reads this page". The note shows for each read, also when the notes are off.
4. earshot reads the page and sends one or more lines:

   ```json
   {"type":"pageText","re":"8C1F…","part":1,"of":2,"complete":true,"url":"https://fox.example/a","title":"Fox facts","blocks":[{"t":"Fox facts","k":"h","level":1,"zone":"main","inMain":true,"links":0}]}
   {"type":"pageText","re":"8C1F…","part":2,"of":2,"complete":true,"blocks":[{"t":"The fox is red.","k":"p","zone":"main","inMain":true,"links":0}]}
   ```

   If earshot does not send text, it sends one line with the reason:

   ```json
   {"type":"pageText","re":"8C1F…","error":"not a web page"}
   ```

The keys of a line:

| Key | Meaning |
|---|---|
| `part`, `of` | The number of this line, and the number of lines. Each line is smaller than 60 KB. |
| `complete` | False if a limit stopped the read. The limits are 5 s, 20,000 elements and 200,000 characters. |
| `url`, `title` | The page address and the window title at the time of the read. Only on part 1. |
| `blocks` | The blocks of the page, in the order of the page. |
| `error` | Why there is no text. |

The keys of a block (a key is absent if earshot does not know its value):

| Key | Meaning |
|---|---|
| `t` | The text. A block longer than 8,000 characters becomes more blocks of the same kind. |
| `k` | The kind: `h` (heading), `p` (paragraph), `li` (list item), `cell` (table cell), `pre` (code) or `q` (quote). |
| `level` | The level of a heading, 1 to 6. |
| `zone` | The nearest landmark that holds the block: `main`, `article`, `nav`, `banner`, `footer`, `aside`, `search`, `form` or `dialog`. |
| `inMain` | True if a `main` or `article` landmark holds the block at some level. |
| `links` | The share of link text in the block, 0 to 1. |

The rules of the read:

- earshot reads the page through Accessibility. It only copies values. It does not press, scroll, select or type, and it does not change the focus.
- earshot never sends the value of a one-line field, a search field, a combo box or a password field. A text area gives its lines.
- earshot sends no text on a sign-in, code or payment page.
- The page in front must be the page of the command. earshot compares the page address at the time of the command, before the read and after the read. It also compares the front app and the front window before and after the read. If one is different, the reason is "the page changed".
- If earshot had no page address at the time of the command, it sends no text.
- A second ask for the same command, an ask after 10 s, and an ask with an unknown id get an error line.
- A plugin whose manifest does not name `pageText` gets no answer to its ask.
- The page text goes only to the plugin. It never goes to the activity log or to Jev.

The reasons for no text: "no Accessibility permission", "no front app", "no front window", "not a web page", "no web page at the time of the command", "the page changed", "sign-in, code or payment page", "no command with this id", "one ask for each command", "too late".

## 6. The example plugin

`app/examples/plugins/echo/` is a small plugin in shell. It answers each command with the number of its words. To try it:

1. Copy the folder `echo` into the plugins folder.
2. In the Plugins tab, click "Read again", and approve "Echo".
3. Hold the key and say "say back the blue fox".
4. The note shows "Echo: 3 words".

## 7. Not in version 1

- "undo that" for the last plugin answer.
