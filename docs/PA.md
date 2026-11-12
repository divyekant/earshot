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

From phase 3, the PA also reads the calendar, Mail and Notes. Do these steps one time:

1. Approve the plugin **PA** again in **Manage > Plugins**, because its manifest changed.
2. If macOS asks for access to the calendar, click **Allow**.
3. If macOS asks "earshot PA wants to control Mail", click **Allow**.
4. If macOS asks "earshot PA wants to control Notes", click **Allow**.

macOS asks these questions only when Mail or Notes runs, because the PA never starts them. A new build of the PA keeps the access. To stop the read of a source, set it to `false` in `sources` in the settings. Then the PA deletes what it kept from that source.

What the PA keeps from a mail: the sender name, the subject and one sentence, only for a flag. 30 days after you answer a flag, the PA deletes its subject and its sentence. The tests used English mail and notes only. The PA does not read a locked note. It cannot open a note for you by voice.

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
| "keep this for kitchen" | Keeps the address and the title of the front page or document. For a file (PDF, text, Markdown, RTF, Word, HTML), the PA also reads its text in the background, so that "where is" can find words in it. For a web page, the PA also keeps the main text of the page (see "Web pages"). |
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
- Near-event alert: 15 minutes before a calendar event with links, the PA shows the event, its time and the linked items and documents. An event with no link gives no alert. If a rule made the link, the record shows with "?". To link an item yourself, say for example "remind me before the dentist to bring the x-ray". In the test, 22 of 24 alerts from the rule were correct. To stop the links by a rule, set `linkEvents` to `false`. Your own links stay.

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
- `kept.html`: the kept web pages, newest first, 200 or fewer. Say "open kept pages".
- `kept/<number>.html`: the text copy of one kept web page.

To open a page, say "open today", "open all open" or "open <project>". You can also open a page in your browser. If an app has the same name as a project, "open <name>" opens the app.

The pages have no script and load nothing from the network. The PA writes the pages again after each change.

## Web pages

When you say "keep this" with a web page in front, the PA keeps the address and the title at once. Then the PA asks earshot for the text of the page. earshot shows "→ PA · reads this page".

1. earshot reads the page in front with Accessibility. It does not click, scroll, select or type.
2. The PA selects the main text: the article, not the menus, the links, the footer or the comments.
3. The PA keeps the main text as passages, so that "where is" finds words in the page. A result line is `Page · <title> · <site> · <words of the page>`.
4. The note shows "Text kept · <title> · 1,240 words".

Other notes:

| Note | Meaning |
|---|---|
| "Text kept in part · <title> · 800 words" | A limit stopped the read, or the page has more than 2,000 passages. The PA keeps what came. |
| "Link kept. The PA has no text of this page." | No text came in 10 s, or the page has fewer than 50 words of main text. The address and the title stay. |
| "Link kept. The PA has no text of this page. Say "keep this" again." | The page changed during the read. |
| "Link kept. The page has a password field, so earshot did not read it." | earshot sends no text of a sign-in, code or payment page. |
| "Kept again · <title> · text updated" | You kept the same page before. The PA keeps one reference and the text of the last read. |

Two addresses are the same page if they are equal without the part after `#` and without the parameters `utm_*`, `fbclid` and `gclid`.

"main points of this" with a web page in front shows 5 sentences of the main text. The PA does not keep the page or its text for this command. "main points of <name>" also finds kept pages.

To delete the text of a page, say "drop" for the page, for example "where is ferry" and then "drop 1". The PA deletes the passages, the numbers and the text copy at once.

Important:

- The PA keeps what the page shows. This also applies to private data of a page behind a sign-in, for example a bank page or an account page. Do not say "keep this" on a page if you do not want its text in the PA.
- The page must be in front and loaded. Text that the page did not load (for example text that shows after a scroll) is not kept.
- A page that you kept before PA 0.4.0 has no text. Say "keep this" again on the page.
- earshot reads web pages in Safari, Chrome and other browsers with a web area. A PDF in Chrome gives text. The PDF view of Safari gives no text. A Slack window or another app is not a web page.
- The tests used English pages only.
- PA 0.4.0 needs an earshot build that knows `pageText` (the first build after 0.5.0). An older earshot does not load the PA.

The setting `pageText` switches the read off. Then "keep this" keeps the address and the title only. The texts that the PA kept stay until you drop them.

## Mail

While the Mail app runs, the PA reads new messages of the inbox each 5 minutes, in small steps. It does not read while Mail is the front app. The PA never starts Mail and never sends, moves, deletes, flags or marks a mail.

The PA makes flags. A flag is one line in a list. It is a proposal: it makes no reminder and no to-do.

- Request flag: `Request · Sam Lee · Could you send me the signed form before the 20th? · 20 Nov?`. The PA selected the sentence from the mail. It writes no words. The day with "?" is a proposed due day.
- Arrival flag: `Arrived? · Sam Lee · Quote for the tiles` if the sender is named in an open "waiting for" item. `New in Kitchen? · mail · Sam Lee · Quote for the tiles` if the mail is like the records of a project.

Limit: the PA finds about half of the requests. Do not use it as your only check of the inbox. When the PA shows a request flag, it is almost always correct. In the tests, 1 of 37 request flags was wrong.

The PA gives a request flag only if all of these are true:

- The mail is not bulk, list, automatic or junk mail, and you did not send it or reply to it.
- The mail is for you: the greeting or the sentence names you, or you are in To with 3 addresses or fewer.
- A person wrote it, or an organization asks you to do a thing with a time limit about a thing of yours (a bill, an appointment, an order). Sales and surveys get no flag.

| You say | The PA does |
|---|---|
| "what is new" | Shows the open flags, newest first. |
| "keep 2" | Makes a to-do from flag 2. The title is the sentence. The to-do has a link to the mail. "keep 2 as call Sam about the form" uses your words. "keep 2 for kitchen" sets the project. |
| "drop 2" | Drops flag 2. |

If you reply to the mail in Mail, the flag goes away at the next read. To stop request flags, set `rules.request` to `off`.

Say "open flags" to see the open flags on a page. Each flag has a link that opens the mail in Mail.

The PA learns from your answers:

- Each "keep" and each "drop" on a request flag is an answer. After 50 answers with 10 or more of each kind, the PA changes its weights a little after each answer. The PA uses the new weights only if they agree better with your last 20 answers than the base weights do.
- The PA makes few wrong flags, so the learning can start late, or never.
- If you drop 3 flags from one sender and keep none, the PA makes no more request flags from that sender. The Today page shows the sender under "No more flags from". To get flags from that sender again, delete the address from `flagsMuted` in the settings.
- To stop the learning, set `flagsLearn` to `false`.

## Notes

While the Notes app runs, the PA reads your notes each 15 minutes. It skips locked notes and the folder "Recently Deleted". "where is" then finds the words of a note. The result shows the note name and the passage. The PA cannot open a note for you: open it in Notes. If a note changes, the PA reads it again. If you delete a note, the PA deletes its passages at the next read. The PA never starts Notes and never changes a note.

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
| `rules` | time alert, due list, silence list, nearEvent alert, newArrival list, request list | Each rule is `"alert"`, `"list"` or `"off"`. |
| `projects` | `{}` | Rules for one project. Example: `{"kitchen": {"due": "alert"}}`. |
| `reminders` | `{"copy": true, "list": "earshot", "alertBy": "reminders"}` | The copy in Apple Reminders. If `alertBy` is `"pa"`, the PA gives the alerts. |
| `projectFocusMinutes` | `5` | After "new project kitchen", your next captures go to Kitchen for this count of minutes. Each capture starts the minutes again. `0` switches it off. |
| `proposeProject` | `true` | If `true`, the PA proposes a project for a capture with no project, with a "?" ("To-do · Kitchen? · call the tiler"). Set it to `false` to stop the proposals. |
| `proposeByName` | `false` | If `true`, the PA also proposes a project whose name is in the capture. Off by default: a name in another sense ("the soup kitchen", "his Lisbon trip") gives a wrong proposal. Say "for <project>" to name a project for sure. |
| `nearEventMinutes` | `15` | The near-event alert comes this count of minutes before the start of an event. |
| `linkEvents` | `true` | If `true`, a rule links open items and documents to a calendar event, shown with "?". If `false`, only your own links ("before the dentist") stay. |
| `sources` | `{"calendar": true, "mail": true, "notes": true}` | The sources that the PA reads. If you set one to `false`, the PA deletes what it kept from that source. |
| `mail` | `{"everyMinutes": 5, "firstDays": 3, "maxPerRead": 50, "batch": 10}` | The mail read: the time between two reads, the days of the first read, the most messages to look back, and the ids in one step. |
| `flagsLearn` | `true` | If `true`, the request flags learn from your "keep" and "drop" answers. If `false`, the PA uses the base weights. |
| `flagsMuted` | `[]` | Sender addresses that get no more request flags. The PA adds an address after you drop 3 flags from it and keep none. Delete an address to get its flags again. |
| `pageText` | `true` | If `true`, "keep this" on a web page also keeps the main text of the page. If `false`, the PA does not ask for page text. |
| `pagePoints` | `true` | If `true`, "main points" works for web pages. If `false`, the answer is "Main points work for kept files only." |
| `searchModel` | `"gemma"` | The search model: `"gemma"`, `"gemma2"`, `"qwen3"` or `"none"` (keywords only). The PA reads it at its start. Run `PA_MODEL=<name> scripts/install-pa.sh` to download another model. |

If the file has an error, the PA uses the default values and shows one note.

## Data

All data stays in `~/Library/Application Support/earshot/plugin-data/pa/`:

- `pa.sqlite`: the store. It keeps the path of each kept file, not its text.
- `kept-text/`: the main text of each kept web page, for "main points". "drop" deletes it.
- `index.sqlite`: the text of kept files and kept web pages, and the numbers of the search model. The PA can make it again from the kept files. It has no daily copy. If you drop a document or a kept folder, the PA deletes its text and its numbers at once (R-PA-9).
- `models/`: the search model file.
- `backups/`: one copy of the store each day. The PA keeps 7 copies.
- `pa.log`: times, event types and record numbers. The log has no words of yours.

The PA removes dropped items after 30 days.
