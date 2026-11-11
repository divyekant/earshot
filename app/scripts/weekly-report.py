#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Weekly report of earshot use, from the activity log (gap item 1).

Text in, text out. The script reads activity.jsonl and prints counts, rates and times.
It never prints the heard words, the intent text, labels, names or message text.

Usage:
    uv run app/scripts/weekly-report.py [--log PATH] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--days N]

With no dates, the report covers the last 7 days. The default log is
~/Library/Application Support/earshot/activity.jsonl. Hours are in the local time zone of the computer.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

# JSONEncoder writes a Date as seconds since 2001-01-01 00:00 UTC (the Apple reference date).
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)
DEFAULT_LOG = os.path.expanduser("~/Library/Application Support/earshot/activity.jsonl")
MODES = ("hold", "wake", "follow-up")


def when(record: dict) -> datetime:
    return (APPLE_EPOCH + timedelta(seconds=float(record.get("at", 0)))).astimezone()


def speech_part(note: str) -> str:
    """The speech part of a note: the text after " · speech: ", or an empty string."""
    return note.split(" · speech: ", 1)[1] if " · speech: " in note else ""


def kind(record: dict) -> str:
    """What the record is: a turn with words, or one of the records that are not commands."""
    note = record.get("note", "")
    if note.startswith("wake phrase in another voice"):
        return "rejected wake"
    if note.startswith("wake phrase near misses"):
        return "near miss"
    if note.startswith("wake turn dropped"):
        return "dropped wake turn"
    if note.startswith("follow-up dropped"):
        return "dropped follow-up"
    if note.startswith("voice taught"):
        return "voice taught"
    if note.startswith("no words"):
        return "no words"
    if note.startswith("speech error"):
        return "speech error"
    return "turn"


def mode(record: dict) -> str:
    """hold, wake or follow-up. An always-on turn has a voice part in its speech note; a wake turn has the phrase."""
    note = record.get("note", "")
    k = kind(record)
    if k == "dropped wake turn":
        return "wake"
    if k == "dropped follow-up":
        return "follow-up"
    speech = speech_part(note)
    if 'wake "' in speech:
        return "wake"
    if "voice" in speech:
        return "follow-up"
    return "hold"


def command_type(record: dict) -> str:
    """The type of command, from the shape of the intent text. It reads no words of the text."""
    intent = record.get("intent") or ""
    note = record.get("note", "")
    if " · then " in intent or note.startswith("step ") or re.match(r"^\d+ steps? done", note) or "chain of " in note:
        return "chain"
    if intent.startswith("type: waiting"):
        return "type (armed)"
    if re.fullmatch(r"Type \d+ words?", intent) or record.get("kind") == "dictation":
        return "typed text (armed or go-on)"
    if "dictation into the focused field" in note:
        return "dictation (hold key)"
    if intent.startswith('Type "'):
        return "type into field" if '" in ' in intent else "type"
    if intent.startswith("→ "):
        parts = intent[2:].split(" · ")
        if len(parts) == 1:
            return "open app"
        return "chat + message" if any(p.startswith("type ") for p in parts[2:]) else "chat"
    if intent.startswith("Click menu "):
        return "menu"
    if intent.startswith("Click ") and intent.endswith("(screen)"):
        return "click (screen picture)"
    if intent.startswith("Click "):
        return "click"
    if intent.startswith("Scroll "):
        return "scroll"
    if intent.startswith("Open "):
        return "open web address"
    if intent == "Send":
        return "send"
    if intent == "Back":
        return "back"
    if intent in ("Show numbers", "Hide numbers"):
        return "numbers"
    return "no intent"


def outcome(record: dict) -> str:
    note = record.get("note", "")
    if record.get("ok"):
        return "ok"
    if note.startswith("not sure"):
        return "not sure"
    if note.startswith("not a command") or note.startswith("not for earshot"):
        return "not a command"
    if note.startswith("send needs") or "blocked" in note.split(" · ")[0]:
        return "blocked"
    return "failed"


def short_reason(text: str) -> str:
    """A reason with no label, name or number: cut at the first quote, digit, bracket, comma or semicolon."""
    cut = re.split(r'["“”…(\[;,:·→›@\d]', text, maxsplit=1)[0]
    return cut.strip() or "(other)"


def end_wait(note: str) -> float | None:
    """The quiet time at the end of an always-on turn, in ms ("end quiet: 560 ms quiet of 550 ms")."""
    found = re.findall(r"end (\w+): (\d+(?:\.\d+)?) ms quiet", note)
    return float(found[-1][1]) if found else None


def end_rule(note: str) -> str | None:
    found = re.findall(r"end (\w+): \d", note)
    return found[-1] if found else None


def total(record: dict) -> float | None:
    stages = record.get("stages") or {}
    if "total" in stages:
        return float(stages["total"])
    times = [v for k, v in stages.items() if k not in ("speech.audio", "dictation.armed")]
    return float(max(times)) if times else None


def pct(values: list[float], p: float) -> float | None:
    """Nearest-rank percentile, the same method as ActivityStats.percentile in the app."""
    if not values:
        return None
    s = sorted(values)
    rank = math.ceil(p * len(s))
    return s[min(max(rank, 1), len(s)) - 1]


def ms(v: float | None) -> str:
    return "–" if v is None else f"{v:.0f}"


def share(a: int, b: int) -> str:
    return "–" if b == 0 else f"{100 * a / b:.0f} %"


def table(head: list[str], rows: list[list[str]]) -> str:
    widths = [max(len(str(x)) for x in col) for col in zip(head, *rows)] if rows else [len(h) for h in head]
    line = lambda r: "| " + " | ".join(str(x).ljust(w) for x, w in zip(r, widths)) + " |"
    sep = "|" + "|".join("-" * (w + 2) for w in widths) + "|"
    return "\n".join([line(head), sep] + [line(r) for r in rows])


def load(path: str) -> list[dict]:
    records = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def report(records: list[dict], start: datetime, end: datetime) -> str:
    rs = [r for r in records if start <= when(r) < end]
    out: list[str] = []
    say = out.append
    say(f"# earshot weekly report, {start:%Y-%m-%d} to {(end - timedelta(seconds=1)):%Y-%m-%d}")
    say("")
    say("No message text, labels or names are in this report. Times are in ms from the end of speech.")
    say("")
    kinds = Counter(kind(r) for r in rs)
    turns = [r for r in rs if kind(r) == "turn"]
    say(f"Records: {len(rs)}. Turns with words: {len(turns)}, "
        f"ok {sum(1 for r in turns if r.get('ok'))} ({share(sum(1 for r in turns if r.get('ok')), len(turns))}).")
    say("")
    say(table(["Record", "Count"], [[k, str(v)] for k, v in kinds.most_common()]))
    say("")

    # 1. Success for each command type.
    say("## 1. Success for each command type")
    say("")
    by_type: dict[str, list[dict]] = defaultdict(list)
    for r in turns:
        by_type[command_type(r)].append(r)
    rows = []
    for t, group in sorted(by_type.items(), key=lambda kv: -len(kv[1])):
        o = Counter(outcome(r) for r in group)
        totals = [x for x in map(total, group) if x is not None]
        rows.append([t, str(len(group)), str(o["ok"]), share(o["ok"], len(group)), str(o["not sure"]),
                     str(o["not a command"]), str(o["blocked"]), str(o["failed"]), ms(pct(totals, 0.5)), ms(pct(totals, 0.9))])
    say(table(["Type", "Turns", "OK", "OK %", "Not sure", "Not a command", "Blocked", "Failed", "Median", "p90"], rows))
    say("")
    unsure = Counter(short_reason(r["note"].split(" · ")[0][len("not sure:"):]) for r in turns if outcome(r) == "not sure")
    if unsure:
        say("Not sure, by reason: " + ", ".join(f"{k} {v}" for k, v in unsure.most_common()) + ".")
        say("")
    failed = Counter(short_reason(r["note"].split(" · ")[0]) for r in turns if outcome(r) == "failed")
    if failed:
        say("Failed, by first note part: " + ", ".join(f"{k} {v}" for k, v in failed.most_common(12)) + ".")
        say("")

    # Chat stages, for the chat flow (R-SP-1).
    chats = [r for r in turns if command_type(r) in ("chat", "chat + message")]
    if chats:
        say("Chat stages (median ms, chat turns that ran an action):")
        say("")
        stage_values: dict[str, list[float]] = defaultdict(list)
        for r in chats:
            for k, v in (r.get("stages") or {}).items():
                stage_values[k].append(float(v))
        rows = [[k, str(len(v)), ms(pct(v, 0.5)), ms(pct(v, 0.9))]
                for k, v in sorted(stage_values.items(), key=lambda kv: pct(kv[1], 0.5) or 0)]
        say(table(["Stage", "Turns", "Median", "p90"], rows))
        say("")

    # 2. Wakes and rejects for each hour.
    say("## 2. Wakes and rejects for each hour (local time)")
    say("")
    hours: dict[int, Counter] = defaultdict(Counter)
    for r in rs:
        h = when(r).hour
        k = kind(r)
        m = mode(r)
        if k == "rejected wake":
            hours[h]["rejected"] += 1
        elif k == "near miss":
            n = re.search(r"near misses: (\d+)", r.get("note", ""))
            hours[h]["near-miss phrases"] += int(n.group(1)) if n else 1
        elif m == "wake":
            hours[h]["wakes"] += 1
            if k == "dropped wake turn":
                hours[h]["wake dropped"] += 1
        elif m == "follow-up":
            hours[h]["follow-ups"] += 1
            if k == "dropped follow-up":
                hours[h]["follow-up dropped"] += 1
    cols = ["wakes", "wake dropped", "rejected", "near-miss phrases", "follow-ups", "follow-up dropped"]
    rows = [[f"{h:02d}"] + [str(hours[h][c]) for c in cols] for h in sorted(hours)]
    rows.append(["all"] + [str(sum(hours[h][c] for h in hours)) for c in cols])
    say(table(["Hour"] + cols, rows))
    say("")
    say("One near-miss record can count several phrases, so this column can be larger than the near-miss record count.")
    say("")
    scores = [float(m.group(1)) for r in rs if kind(r) == "rejected wake"
              for m in [re.search(r"score (-?\d+\.\d+)", r.get("note", ""))] if m]
    if scores:
        say(f"Rejected wake voice scores: min {min(scores):.2f}, median {pct(scores, 0.5):.2f}, "
            f"p90 {pct(scores, 0.9):.2f}, max {max(scores):.2f}.")
        say("")

    # 3. Dropped turns.
    say("## 3. Dropped turns")
    say("")
    dropped = Counter()
    for r in rs:
        if kind(r) in ("dropped wake turn", "dropped follow-up"):
            why = r["note"].split("dropped: ", 1)[1].split(" · ")[0]
            dropped[(kind(r), short_reason(why))] += 1
    rows = [[k, why, str(v)] for (k, why), v in dropped.most_common()]
    say(table(["Record", "Reason", "Count"], rows) if rows else "None.")
    say("")
    wake_turns = sum(1 for r in rs if mode(r) == "wake" and kind(r) in ("turn", "no words", "dropped wake turn"))
    voice_drops = sum(1 for r in rs if kind(r) == "dropped wake turn" and "not the owner's voice" in r["note"])
    say(f"Wake turns that got the start sound, then failed the voice check of the turn: {voice_drops} "
        f"of {wake_turns} wake turns ({share(voice_drops, wake_turns)}).")
    follow_nc = sum(1 for r in turns if mode(r) == "follow-up" and r.get("note", "").startswith("not a command"))
    follow_all = sum(1 for r in turns if mode(r) == "follow-up")
    say(f"Follow-up turns with words that ended \"not a command\": {follow_nc} of {follow_all}.")
    say("")

    # 4. Turns with no words, for each mode.
    say("## 4. Turns with no words, for each mode")
    say("")
    rows = []
    for m in MODES:
        heard = [r for r in rs if mode(r) == m and kind(r) in ("turn", "no words", "speech error")]
        none = sum(1 for r in heard if kind(r) == "no words")
        rows.append([m, str(len(heard)), str(none), share(none, len(heard))])
    say(table(["Mode", "Turns to the speech engine", "No words", "Share"], rows))
    say("")

    # 5. Time with the end wait.
    say("## 5. Time with the end wait")
    say("")
    say("The command time is the total stage. In always-on mode, the end wait is the quiet time before the turn ended.")
    say("The hold key has no end wait: the total includes the tail after the key goes up.")
    say("")
    rows = []
    for m in MODES:
        group = [r for r in turns if mode(r) == m]
        totals = [x for x in map(total, group) if x is not None]
        both = [total(r) + end_wait(r["note"]) for r in group
                if total(r) is not None and end_wait(r.get("note", "")) is not None] if m != "hold" else totals
        waits = [w for w in (end_wait(r.get("note", "")) for r in group) if w is not None]
        rows.append([m, str(len(group)), ms(pct(totals, 0.5)), ms(pct(totals, 0.9)), ms(pct(waits, 0.5)),
                     ms(pct(both, 0.5)), ms(pct(both, 0.9))])
    say(table(["Mode", "Turns", "Command median", "Command p90", "End wait median", "With wait median",
               "With wait p90"], rows))
    say("")
    rules = Counter(end_rule(r.get("note", "")) for r in rs if mode(r) != "hold" and end_rule(r.get("note", "")))
    if rules:
        say("Always-on turn ends, by rule: " + ", ".join(f"{k} {v}" for k, v in rules.most_common()) + ".")
        say("")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--log", default=DEFAULT_LOG, help="the activity.jsonl file")
    ap.add_argument("--since", help="first day, YYYY-MM-DD (local time)")
    ap.add_argument("--until", help="last day, YYYY-MM-DD (local time), included")
    ap.add_argument("--days", type=int, default=7, help="days before --until when --since is not given (default 7)")
    a = ap.parse_args(argv)
    local = datetime.now().astimezone().tzinfo
    day = lambda s: datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=local)
    end = day(a.until) + timedelta(days=1) if a.until else datetime.now().astimezone() + timedelta(seconds=1)
    start = day(a.since) if a.since else end - timedelta(days=a.days)
    try:
        records = load(a.log)
    except OSError as e:
        print(f"Cannot read the log: {e}", file=sys.stderr)
        return 1
    print(report(records, start, end))
    return 0


if __name__ == "__main__":
    sys.exit(main())
