# The PA plugin

The PA plugin keeps your reminders, to-dos, notes, documents and projects. PA means personal assistant. The PA is the first plugin of earshot (`docs/PLUGINS.md`). It is experimental.

The PA works only on your Mac. It has no network code and no language model. It does not send your words to Jev. It reads times with fixed rules.

## Install

1. Build and install the plugin. In a terminal, go to the earshot folder. Then run this command:

   ```sh
   plugins/pa/scripts/install-pa.sh
   ```

2. Quit earshot, then start earshot again.
3. In earshot, open **Manage > Plugins**.
4. Approve the plugin **PA**.
5. If macOS asks for access to Reminders, click **Allow**.

The script does not approve the plugin. The script does not restart earshot. If you install a new version and `plugin.json` changes, approve the plugin again.

After you install a new version, click **Read again** in **Manage > Plugins** to start the new program. An earshot build from before 2026-11-11 keeps the old program. In that case, turn **Approved** off and on for **PA**.

## Commands

Hold the earshot key and say one of these commands.

| You say | The PA does |
|---|---|
| "remind me to call the plumber at 5" | Saves a reminder at 17:00 and shows an alert at that time. |
| "todo send the tax papers by Friday" | Saves a to-do that is due on Friday. "task" is the same. |
| "note the landlord wants two months notice" | Saves a note. The PA does not read a time in a note. |
| "keep this for kitchen" | Keeps the address and the title of the front page or document. |
| "new project kitchen" | Makes the project "Kitchen". For 5 minutes, your next captures go to Kitchen. |
| "what is due" | Shows late items, the reminders of today, and the to-dos of today and tomorrow. "what's due" is the same. |
| "what about kitchen" | Shows the open items of the project. |
| "where is passport" | Shows the items, documents, projects and passages of kept files that match. With the search model, it also finds results in other words ("the offer for the tiles" finds a quote). "open search" shows 10 results with more text. |
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
- `project-<name>.html`: one page for each open project.

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
| `proposeProject` | `false` | If `true`, the PA proposes a project for a capture with no project, with a "?" ("To-do · Kitchen? · call the tiler"). Off by default: the proposals did not pass the test of E10. |
| `searchModel` | `"gemma"` | The search model: `"gemma"`, `"qwen3"` or `"none"` (keywords only). The PA reads it at its start. Run `PA_MODEL=<name> scripts/install-pa.sh` to download another model. |

If the file has an error, the PA uses the default values and shows one note.

## Data

All data stays in `~/Library/Application Support/earshot/plugin-data/pa/`:

- `pa.sqlite`: the store.
- `index.sqlite`: the text of kept files and the numbers of the search model. The PA can make it again from the kept files. It has no daily copy.
- `models/`: the search model file.
- `backups/`: one copy of the store each day. The PA keeps 7 copies.
- `pa.log`: times, event types and record numbers. The log has no words of yours.

The PA removes dropped items after 30 days.
