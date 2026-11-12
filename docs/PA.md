# The PA plugin

The PA plugin keeps your reminders, to-dos, notes, documents and projects. PA means personal assistant. The PA is the first plugin of earshot (`docs/PLUGINS.md`). It is experimental.

The PA works only on your Mac. It has no network code. It does not send your words to Jev. It reads times with fixed rules.

The PA has one small search model (EmbeddingGemma-300M, about 334 MB, D-16). The model turns a text into a list of numbers, so that the search can find a document by its meaning. The model does not write text. The PA shows only your words, the words of your kept documents, fixed labels, times and counts (R-PA-4).

The model runs in a separate worker process (`earshot-pa --embed-worker`). The worker reads no file and has no access to the store: the PA sends it the texts. The worker starts at the first use of the model and stops after 5 minutes with no use, so that its memory goes back to the Mac. If the worker stops or gives no answer in 10 seconds, the PA answers the command with the keyword search, and the next use starts a new worker (R-PA-8).

## Install

1. Build and install the plugin. In a terminal, go to the earshot folder. Then run this command:

   ```sh
   plugins/pa/scripts/install-pa.sh
   ```

2. Quit earshot, then start earshot again.
3. In earshot, open **Manage > Plugins**.
4. Approve the plugin **PA**.
5. If macOS asks for access to Reminders, click **Allow**.

The script also downloads the search model to the data folder of the PA, with a SHA-256 check. The PA program itself has no network code. To use no model, run `PA_MODEL=none plugins/pa/scripts/install-pa.sh` and set `"searchModel": "none"`. Then the search uses keywords only.

The first time that you keep a file in Documents, Desktop or Downloads, macOS can ask if the PA can open files in that folder. Click **Allow** if you want the PA to find words in the file. If you click **Don't Allow**, the PA keeps the reference and shows one note: "The PA cannot read this folder. The reference is kept."

The script does not approve the plugin. The script does not restart earshot. If you install a new version and `plugin.json` changes, approve the plugin again.

After you install a new version, click **Read again** in **Manage > Plugins** to start the new program. An earshot build from before 2026-11-11 keeps the old program. In that case, turn **Approved** off and on for **PA**.

## Commands

Hold the earshot key and say one of these commands.

| You say | The PA does |
|---|---|
| "remind me to call the plumber at 5" | Saves a reminder at 17:00 and shows an alert at that time. |
| "todo send the tax papers by Friday" | Saves a to-do that is due on Friday. "task" is the same. |
| "note the landlord wants two months notice" | Saves a note. The PA does not read a time in a note. |
| "keep this for kitchen" | Keeps the address and the title of the front page or document. For a file (PDF, text, Markdown, RTF, Word, HTML), the PA also reads its text in the background, so that "where is" can find words in it. |
| "note this" | Saves the selected text as a note (2,000 characters or fewer), with a link to the document or page. With no selection, "note this" is a normal note. |
| "new project kitchen" | Makes the project "Kitchen". For 5 minutes, your next captures go to Kitchen. |
| "what is due" | Shows late items, the reminders of today, and the to-dos of today and tomorrow. "what's due" is the same. |
| "what about kitchen" | Shows the open items of the project. |
| "what projects" | Shows the open projects, each with its count of open items. |
| "finish project kitchen" | Closes the project. Its open items stay open. "new project kitchen" opens it again. |
| "where is passport" | Shows the items, documents, projects and passages of kept files that match. With the search model, it also finds results in other words ("the offer for the tiles" finds a quote). "open search" shows 10 results with more text. |
| "keep this folder for kitchen" | Keeps the front folder in Finder and reads its files (3 levels or fewer, 500 files or fewer). A new file in the folder is read at once and shows as "New in Kitchen · quote-2.pdf" in the morning list and on the project page (rule `newArrival`). |
| "main points of this" | Shows 5 sentences of the front document that give its main points. "main points of the roof estimate" uses the best kept document for the words. "main points 2" uses item 2 of the last list. "summarize" is the same. "open main points" shows the full sentences. The PA selects sentences of the document. It writes no new words. |
| "done 2" | Marks item 2 of the last list as done. "done that" uses the last alert. |
| "snooze 2 to tomorrow" | Moves the time of item 2. With no time, the PA uses 10 minutes. |
| "drop 2" | Removes item 2 from the open lists. |
| "move 2 to garden" | Puts item 2 in the project "Garden". |
| "quiet for 2 hours" | Stops the alerts until that time. "quiet off" starts them again. |

More rules:

- To put an item in a project, say "for <project>" or "in <project>" at the end. Example: "todo order the paint for kitchen".
- The PA saves your words in all cases. If the PA is not sure of the time, it saves the item with no time. The note then shows "no time".
- If you say the same capture two times in 60 seconds, the PA keeps one.
- A list shows 10 lines or fewer. If there are more items, the last line is "and N more".
- The PA never selects text and never writes text in an app.
- The project focus: after "new project kitchen", a capture with no project goes to Kitchen for 5 minutes. Each capture starts the 5 minutes again. "new project" with another name, or "move it to no project", ends the focus. Set `projectFocusMinutes` to `0` to stop it.
- The "?" mark: if `proposeProject` is `true`, the PA can propose a project for a capture with no project. The second note shows it with a "?": "To-do · Kitchen? · call the tiler". Lists and pages show the "?" until you confirm it. Say "move it to kitchen" to confirm, or "move it to garden" or "move it to no project" to correct it. The Today page counts the proposals and the corrections of the last 7 days. If more than 1 in 5 of 10 or more proposals were wrong, the page says so. Proposals are on by default. The PA proposes a project only if two signals agree (see "How the PA proposes a project"). To put a capture in a project for sure, say "for <project>" or "in <project>" at the end.
- The similar-item note: if a new to-do or reminder is like an open one, a second note says "To-do · like one that you have: order the paint". The PA keeps both.
- Main points are 5 sentences of the document, in the order of the document. The PA selects them. It does not write a summary and does not change a word. Each sentence gets points: for an amount of money, a date or a time limit, a request to the reader, a result such as a price or a decision, words of the title, and a central place in the text. A heading, a sign-off or legal small print gets no points. They are not always the most important sentences. In the test of the follow-up, 2 or more of the 3 marked key sentences were in the 5 for 10 of 10 new documents.
- How the PA proposes a project: the PA uses only the records that you put in a project (items that you moved or captured into it, and the passages of documents with a project). A project needs 3 or more of these records. 4 or more of the 5 nearest records must be in the project, and the first 3 results of a keyword search must all be in the same project. A project name in the capture alone gives no proposal, because the same words can have another sense ("the soup kitchen"). Set `proposeByName` to `true` to also propose a project whose name is in the capture. The sure way to name a project is "for <project>" at the end: then the PA puts the capture in the project, with no "?". In the test of the follow-up, 19 of 20 proposals were correct. The PA proposes a project for few captures: 19 of 70 captures with a project got a proposal.

## Alerts

- The PA shows an alert at the time of a reminder. If you do not answer, it shows the alert one more time after 10 minutes.
- At 09:00, the PA shows a list of the items of the day.
- The PA shows 3 alerts or fewer in one hour.
- In quiet hours (22:00 to 08:00), the PA keeps the alerts for later. A reminder with a clock time that you said in quiet hours still gives an alert.
- If earshot was not on at the time of an alert, the PA shows a list "Missed" at the next start.
- If the copy in Apple Reminders is on, Reminders gives the alert of a reminder. The PA does not give a second alert.

## The copy in Apple Reminders

The PA copies each open to-do and reminder to the Reminders list "earshot". macOS copies the list to your iPhone through iCloud.

- The PA store is the source. The Reminders list is a copy.
- If you tick a reminder on the iPhone, the PA marks the item as done.
- If you change a title or a time in the list, the PA changes the item.
- If you delete a reminder in the list, the PA drops the item.
- If you add a reminder to the list "earshot" on the iPhone, the PA saves it as a new item.
- The PA copies the title, the time and the project name. It does not copy notes, documents or your full words.
- The PA does not read or change other Reminders lists.

> **CAUTION:** If you set `"copy": false`, the PA reads the list one last time and then removes the list "earshot" from Reminders. The items stay in the PA store.

If the PA has no access to Reminders, it shows the note "The PA has no access to Reminders. The copy is off." All other functions continue to work. To give access, open **System Settings > Privacy & Security > Reminders** and turn on **earshot PA**.

## Pages

The PA writes HTML pages in this folder:

```
~/Library/Application Support/earshot/plugin-data/pa/pages/
```

- `today.html`: late items, today, tomorrow, the quiet items, and the counts of the last 7 days.
- `all-open.html`: all open items, by project.
- `project-<name>.html`: one page for each open project, with its documents, its kept folders and the new files of the last 7 days.
- `search.html`: the 10 results of the last "where is", with more text and the file path. Say "open search".
- `main-points.html`: the 5 sentences of the last "main points", each with its page. Say "open main points".

To open a page, say "open today", "open all open" or "open <project>". You can also open a page in your browser. If an app has the same name as a project, "open <name>" opens the app.

The pages have no script and load nothing from the network. The PA writes the pages again after each change.

## Settings

The settings file is `~/Library/Application Support/earshot/plugin-data/pa/settings.json`. The PA writes the file with the default values at the first start. The PA reads the file again when it changes.

| Key | Default | Meaning |
|---|---|---|
| `morningTime` | `"09:00"` | The time of the morning list. |
| `quietHours` | `{"from": "22:00", "to": "08:00"}` | No alerts in this time. |
| `maxAlertsPerHour` | `3` | The most alerts in one hour. |
| `repeatAfterMinutes` | `10` | The time before an alert shows again. |
| `defaultSnoozeMinutes` | `10` | The snooze time if you say no time. |
| `bareHourWindow` | `{"from": "07:00", "to": "23:00"}` | "at 5" is the next 5 o'clock in this window. |
| `dayParts` | morning 09:00, noon 12:00, afternoon 15:00, evening 18:00, tonight 20:00, endOfDay 17:00 | The times of these words. |
| `rules` | time alert, due list, silence list, nearEvent alert, newArrival list | Each rule is `"alert"`, `"list"` or `"off"`. |
| `projects` | `{}` | Rules for one project. Example: `{"kitchen": {"due": "alert"}}`. |
| `reminders` | `{"copy": true, "list": "earshot", "alertBy": "reminders"}` | The copy in Apple Reminders. If `alertBy` is `"pa"`, the PA gives the alerts. |
| `projectFocusMinutes` | `5` | After "new project kitchen", your next captures go to Kitchen for this count of minutes. Each capture starts the minutes again. `0` switches it off. |
| `proposeProject` | `true` | If `true`, the PA proposes a project for a capture with no project, with a "?" ("To-do · Kitchen? · call the tiler"). Set it to `false` to stop the proposals. |
| `proposeByName` | `false` | If `true`, the PA also proposes a project whose name is in the capture. Off by default: a name in another sense ("the soup kitchen", "his Lisbon trip") gives a wrong proposal. Say "for <project>" to name a project for sure. |
| `searchModel` | `"gemma"` | The search model: `"gemma"`, `"gemma2"`, `"qwen3"` or `"none"` (keywords only). The PA reads it at its start. Run `PA_MODEL=<name> scripts/install-pa.sh` to download another model. |

If the file has an error, the PA uses the default values and shows one note.

## Data

All data stays in `~/Library/Application Support/earshot/plugin-data/pa/`:

- `pa.sqlite`: the store. It keeps the path of each kept file, not its text.
- `index.sqlite`: the text of kept files and the numbers of the search model. The PA can make it again from the kept files. It has no daily copy. If you drop a document or a kept folder, the PA deletes its text and its numbers at once (R-PA-9).
- `models/`: the search model file.
- `backups/`: one copy of the store each day. The PA keeps 7 copies.
- `pa.log`: times, event types and record numbers. The log has no words of yours.

The PA removes dropped items after 30 days.
