"""Tests of weekly-report.py. Run: python3 -m unittest discover -s app/scripts -p 'test_*.py'"""

import importlib.util
import json
import os
import tempfile
import unittest
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("weekly_report", os.path.join(HERE, "weekly-report.py"))
wr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wr)

AT = (datetime(2026, 11, 5, 10, tzinfo=timezone.utc) - wr.APPLE_EPOCH).total_seconds()


def rec(heard, intent, ok, note, stages=None):
    return {"at": AT, "heard": heard, "intent": intent, "tier": "rules", "ok": ok, "note": note, "stages": stages or {}}


RECORDS = [
    rec("Slack Ravi, (2 words)", '→ Slack · Ravi Example · type "(2 words)"', True,
        'typed · route: name · speech: wake "hey atlas", voice 0.50 · turn voice 0.60 · end quiet: 560 ms quiet of 550 ms, turn 2140 ms',
        {"speech": 200, "speech.audio": 3000, "action.focus": 700, "total": 1100}),
    rec("open notes", "→ Notes", True, "opened · speech: turn voice 0.55 · end model: 300 ms quiet of 300 ms, turn 900 ms",
        {"total": 300}),
    rec("go to secret place", "→ Slack · Secret Person", False, "not sure: two chats match · maybe → Slack · Secret Person",
        {"total": 250}),
    rec("blah", "none", False, 'not a command · route: no command word · speech: turn voice 0.5', {"total": 90}),
    rec("", "none", False, "no words · speech: parakeet audio 900 ms", {"speech": 80, "total": 85}),
    rec("", "none", False, "wake phrase in another voice (score 0.21, needs 0.35), match 0.25, worst part 0.20"),
    rec("", "none", False, "wake phrase near misses: 2, best template score 0.36"),
    rec("", "none", False, "wake turn dropped: not the owner's voice (0.20) · wake \"hey atlas\", voice 0.40"),
    rec("", "none", False, "follow-up dropped: follow-up too short for a voice check"),
]


class ReportTests(unittest.TestCase):
    def run_report(self):
        start = datetime(2026, 11, 1, tzinfo=timezone.utc)
        end = datetime(2026, 11, 8, tzinfo=timezone.utc)
        return wr.report(RECORDS, start, end)

    def test_no_text_in_the_report(self):
        text = self.run_report()
        for secret in ["Ravi", "Secret", "Notes", "blah", "secret place", "(2 words)"]:
            self.assertNotIn(secret, text)

    def test_counts(self):
        self.assertEqual(wr.mode(RECORDS[0]), "wake")
        self.assertEqual(wr.mode(RECORDS[1]), "follow-up")
        self.assertEqual(wr.mode(RECORDS[4]), "hold")
        self.assertEqual(wr.command_type(RECORDS[0]), "chat + message")
        self.assertEqual(wr.command_type(RECORDS[1]), "open app")
        self.assertEqual(wr.outcome(RECORDS[2]), "not sure")
        self.assertEqual(wr.kind(RECORDS[7]), "dropped wake turn")
        self.assertEqual(wr.end_wait(RECORDS[0]["note"]), 560)
        self.assertEqual(wr.total(RECORDS[0]), 1100, "the total stage, not the audio length")
        text = self.run_report()
        self.assertIn("Turns with words: 4", text)
        self.assertIn("then failed the voice check of the turn: 1 of 2 wake turns", text)
        self.assertIn('ended "not a command": 1 of 2', text)
        self.assertIn("two chats match 1", text)

    def test_main_reads_a_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
            for r in RECORDS:
                f.write(json.dumps(r) + "\n")
            f.write("not json\n")
        try:
            self.assertEqual(wr.main(["--log", f.name, "--since", "2026-11-01", "--until", "2026-11-08"]), 0)
            self.assertEqual(wr.main(["--log", f.name + ".missing"]), 1)
        finally:
            os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
