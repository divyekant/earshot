# E1: generic router (rules + Jev, text only)

Status: plan, 2026-11-02. The owner chose "E1 with Jev, text only" and "no local small model now".

E1 follows [E0](E0-viability.md). E0 showed that one sentence can put the cursor in the correct message box in under 1 s. But E0 used data written by hand: the app rows in `probe/apps.json`, the names in `probe/people.json` and a fixed grammar. E1 tests a version with no hand-written data.

## 1. Questions

1. **Catalogue.** Can the probe build the app rows from the menu bar of each app, with no row written by hand (R-MT-1, R-MT-2)?
2. **Index.** Can the probe read the chat names of each chat app from its sidebar through Accessibility (AX), fast enough for a background update?
3. **Router.** The router gets only the words, the catalogue and the index. Which router picks the correct action most often, and how fast: local rules with fuzzy match, Jev, or rules first with Jev only when the rules are unsure?

## 2. Limits

- Audio stays on the Mac. E1 uses typed text, not speech.
- Jev is the TypeSafe "systemone" model (`jev-latest`). It runs in the cloud. E1 sends it only the command words, the owner's name and the option labels (app names and chat names). E1 sends no audio, no screenshot and no message text from the apps.
- Jev in the command path does not agree with R-MD-1 and D-5. The owner approved Jev for this test only, on 2026-11-02. R-MD-1 changes only if the owner decides so after E1.
- No local model in E1. The owner plans to train an own small model later, because the command vocabulary is small. The E1 logs are the first data for it.
- One Jev call for each command at most. There is no agent loop (R-SP-2).
- The Jev key comes from the `TYPESAFE_API_KEY` environment variable, else from `~/.config/jev-qa/env`. The probe never prints, logs or saves the key.
- `catalogue`, `index`, `e1-make`, `e1-try` and `e1-run` press no key, click nothing and type nothing. `index --front` brings each chat app to the front for a moment, and then brings back the app that was in front.
- `e1-open` presses keys to open the owner's own chat (the same as E0 Part A). It types no text. It runs only after the owner agrees.
- `e1-search` presses keys: the search keys of the app, the name, Command-A, Delete and Escape. It never presses Return, so it opens no chat. The owner approved it on 2026-11-02.
- WhatsApp stays out, by the owner's choice in E0.

## 3. Method

### 3.1 Catalogue

`earshot-probe catalogue` reads the menu bar of each regular app that runs. It finds the menu item that opens a chat by its title. The first rule that matches wins:

| Rule | Title words | Chat app |
| --- | --- | --- |
| switch | "jump to", "switch to", "quick switcher", "go to conversation", "go to chat", "go to channel", "find conversation" | yes |
| new message | "new message", "new chat", "new conversation", "new direct message" | yes |
| search | "search", "find" | no |

The probe gives each generated row the E0 defaults: pick the top result with Return, wait 250 ms. The E0 safety guard checks each Return. The spoken names of an app are its name, its bundle names and the last word of a name with two or more words ("Google Chrome" gives "chrome"). The catalogue also lists the installed apps, for "open <app>" commands. The probe compares the generated rows with the E0 rows in `apps.json`.

### 3.2 Index

`earshot-probe index` reads the sidebar of the main window of each chat app. The sidebar ends where the message box starts, and at 42 % of the window at most. In a list row, it takes the text nearest the top left: chat lists show the name there. If the sidebar has list rows, it keeps only the row names, because the loose texts and buttons around them are screen labels. It drops times, dates, counts, notes in brackets and common screen words such as "Threads" or "Inbox". It adds the owner's own chat: a name with "(you)", else the macOS user name.

Electron apps such as Slack build their tree late. The probe reads the sidebar again every 300 ms, up to 8 times, until the list stops changing. It logs the time of one read and the time until the list is stable.

A word with a capital letter inside it in the placeholder of the message box becomes an extra spoken name of the app. Messages shows "iMessage" there. The index stays on the Mac in `probe/logs/index.json`. Git ignores it.

`index --dump` prints the sidebar part of the tree with the role, position and length of each text, and the first 20 characters of each text only.

### 3.3 Test commands

`earshot-probe e1-make` makes about 50 commands from the index, with the correct answers:

| Kind | Example | What it tests |
| --- | --- | --- |
| full | "message Ravi Kumar on Slack" | App and full name |
| app-first | "Slack Ravi" | Short form, first name |
| first-only | "message Ravi" | No app. If two apps show Ravi, both answers are correct |
| misheard | "message Ruvi on Slack" | One wrong vowel, as speech to text can hear |
| with-text | "tell Ravi on Slack that I will be ten minutes late" | Message text after the name |
| self | "Slack me, buy milk" | The owner's own chat |
| spoken-app | "text Ravi on iMessage" | An app name that no menu shows |
| open-app | "open Notes", "switch to Slack" | Open an app, no chat |
| none | "the build passed on the second try" | Not a command |
| free | "can you pull up Ravi on Slack", "get me Ravi's chat" | Phrasings that the rules grammar was not written for |
| unknown | "message Ishaan on Slack" | A name that is not in the index. Doing nothing, or opening only the app, is correct |

The set comes from the owner's real chat names, but the probe writes the sentences. Later work adds the owner's own spoken commands from the logs.

### 3.4 Routers

All routers get the same short list. Step 1 (the probe, on the Mac) makes it: the 8 index entries with the highest fuzzy-match score, an "open the app" option for each app name in the words, and "none".

| Router | Where | How it picks |
| --- | --- | --- |
| Rules + fuzzy | Mac | The top name if its score is 0.8 or more and no second name is close. Else an app name. A sentence with no command word and no app name is "none". The rules also say if they are sure. |
| Jev alone | Cloud | One "choice" question: the words, the owner's name and the option labels |
| Rules, Jev if unsure | Mac, then cloud | The rules answer when the rules are sure. Else the Jev answer |

`earshot-probe e1-run` sends each command through all three and logs the answers and the times. It also counts each wrong chat: a chat that is not the correct one. A wrong chat is the unsafe error, because the owner can then type into the wrong chat.

### 3.5 The app's own search as the name source

The first two runs showed that a sidebar shows only some chats: Slack showed 3 of its chats to Accessibility, and Messages shows only chats with history. But the app's own search knows every chat, and E0 already opens chats through it. `earshot-probe e1-search` tests this source:

1. Bring the app to the front and press its search keys from the catalogue.
2. Type the name. The E0 checks apply: the focus must move to a search field, and the field must show the name.
3. Read the names below the search field, in the same column, until the list stops changing.
4. Select the field text, delete it and press Escape. Never press Return.

For each name, it logs the result names, the time until the list is stable, and the place of the best match. The names are the test contacts, the chat names from the test set, the chat names that another app shows, one misheard name, the owner's name and a name that is not in the owner's chats.

### 3.6 Generated rows open the chat

`earshot-probe e1-open` runs the E0 pipeline with the generated rows: it opens the owner's own chat in each chat app and focuses the box. It types nothing.

## 4. Pass marks

| Check | Go | Change the design | Stop |
| --- | --- | --- | --- |
| Catalogue | The generated Slack and Messages rows have the same keys as the E0 rows | One differs, and a better rule fixes it | No rule finds the keys |
| Index | The owner's own chat and the test contact are in the index for Slack and Messages; under 300 ms for each app | Under 1 s for each app | Names are not readable |
| Router, correct | "Rules, Jev if unsure" is correct for 90 % or more of the commands | 80 % to 90 % | Under 80 % |
| Router, time | "Rules, Jev if unsure": median 50 ms or less, slowest 1 in 10 under 400 ms | Slowest 1 in 10 under 1 s | Over 1 s |
| Rules safety | When the rules are sure, they are correct for 98 % or more | 95 % to 98 % | Under 95 % |
| Wrong chat | "Rules, Jev if unsure" opens no wrong chat | 1 or 2 wrong chats | 3 or more |
| Generated rows | `e1-open` opens the own chat 3 of 3 in each app | 2 of 3 | Under 2 of 3 |
| Search source | `e1-search` finds a matching chat for 9 of 10 known names in each app, in under 600 ms | 7 to 9 of 10, or under 1 s | Under 7 of 10 |

## 5. Results

### 5.1 First run (2026-11-02)

The build, the catalogue and the Jev calls worked. The test itself did not measure much, for two reasons:

- The index held screen labels, not chats. The first sidebar edge (42 %) was wider than the Slack sidebar (about 24 %), so the probe also read message text from the open chat. Slack showed "loading…": its tree was not complete when the probe read it. Messages gave 0 names.
- `e1-make` made the commands from the same index and with the same grammar as the rules. So the rules were correct for 28 of 28, and the score proves little.

Numbers that do count:

| Item | Result |
| --- | --- |
| Catalogue, Slack | Command-K ("Go > Switch to Channel"), the same as the E0 row |
| Catalogue, Messages | Command-N ("File > New Message"), the same as the E0 row |
| Catalogue, one read | 76 to 721 ms for each app (menu bar) |
| Jev, warm call | median 87 ms, slowest 1 in 10: 148 ms, about 500 input tokens |
| Jev, first call | 110 ms |
| Rules | median 9 ms, slowest 1 in 10: 25 ms |

Changes after the first run: the sidebar ends at the message box, the probe reads again until the list is stable, rows win over loose labels, the menu rules match whole words and skip the Apple menu ("find" matched "Finder"), the last word of an app name is not a spoken name if it is a command word ("Sublime Text" gave "text"), and the test set has free phrasings and unknown names.
