"""Tests of the formats, the marks and the sealed run of E13 (build spec 2 and 6, R-FN-4, R-FN-5)."""

import tempfile
import unittest
from pathlib import Path

from footnote_model import bench, marks
from footnote_model.formats import (check_items, check_pairs, label_file, made_up_problems, read_jsonl, read_tsv,
                                    pair_task, same_sentence, write_jsonl, write_tsv, NEED_LABEL_COLUMNS)


def mail(i, body="Could you send the form by Friday?", known=True, kind="mail"):
    return {"id": i, "owner": {"name": "Ana Lim", "address": "ana.lim@example.com"},
            "now": "2026-11-03T08:00:00Z", "from_name": "" if kind == "note" else "Sam Lee",
            "from_address": "" if kind == "note" else "sam@example.org", "to": ["ana.lim@example.com"], "cc": [],
            "subject": "Form", "date": "2026-11-03T08:00:00Z", "list_unsubscribe": False, "precedence": "",
            "auto_submitted": False, "junk": False, "replied": False, "body": body, "sender_known": known}


class FormatTests(unittest.TestCase):
    def test_made_up_domains_only(self):
        self.assertEqual(made_up_problems("mail a@example.com or b@shop.example.org, see https://example.net/x"), [])
        self.assertEqual(made_up_problems("write to bob@gmail.com"), ["bob@gmail.com"])
        self.assertEqual(len(made_up_problems("https://www.realshop.co.uk/a")), 1)

    def test_check_items_finds_a_sentence_that_is_not_in_the_body(self):
        items = [mail("m1")]
        labels = [{"id": "m1", "need": "list", "kind": "person", "sentence": "Pay the bill.",
                   "sentence2": ""}]
        self.assertTrue(any("not in the body" in p for p in check_items(items, labels)))
        labels[0]["sentence"] = "Could you send the form by Friday?"
        self.assertEqual(check_items(items, labels), [])

    def test_a_note_is_never_now(self):
        labels = [{"id": "n1", "need": "now", "kind": "", "sentence": "Could you send the form by Friday?", "sentence2": ""}]
        self.assertTrue(any("never now" in p for p in check_items([mail("n1", kind="note")], labels)))
        labels[0]["need"] = "1"
        self.assertTrue(any("none, list or now" in p for p in check_items([mail("n1", kind="note")], labels)))

    def test_pairs_check(self):
        p = {"id": "p1", "owner": {"name": "Ana Lim", "address": "ana.lim@example.com"},
             "a": {"text": "ring the joiner", "kind": "capture"},
             "b": {"kind": "project", "name": "Kitchen", "records": ["new worktop"]}}
        self.assertEqual(check_pairs([p], [{"id": "p1", "label": "1", "kind": ""}]), [])
        self.assertTrue(check_pairs([dict(p, b={"kind": "other", "name": "x"})], None))
        self.assertEqual(pair_task(Path("fit-a.jsonl")), "fit")
        self.assertEqual(pair_task(Path("close-a.jsonl")), "closes")

    def test_gzip_round_trip_is_stable(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d) / "a.jsonl.gz", Path(d) / "b.jsonl.gz"
            write_jsonl(a, [mail("m1")])
            write_jsonl(b, [mail("m1")])
            self.assertEqual(a.read_bytes(), b.read_bytes())
            self.assertEqual(read_jsonl(a)[0]["id"], "m1")
            self.assertEqual(label_file(a).name, "a-labels.tsv")

    def test_same_sentence_ignores_line_ends(self):
        self.assertTrue(same_sentence("Could you\nsend it?", "Could you send it?"))
        self.assertFalse(same_sentence("", ""))


class MarkTests(unittest.TestCase):
    def test_d1_mail_counts_and_shares(self):
        items = [mail(f"m{i}") for i in range(400)]
        labels = [{"id": f"m{i}", "need": "list" if i < 40 else "none", "kind": "",
                   "sentence": "Could you send the form by Friday?" if i < 40 else "", "sentence2": ""}
                  for i in range(400)]
        preds = {f"m{i}": {"need": "1", "sentence": "Could you send the form by Friday?"} for i in range(34)}
        preds.update({f"m{i}": {"need": "1", "sentence": ""} for i in range(40, 50)})
        r = marks.d1_mail(items, labels, preds)
        self.assertEqual((r.counts["found"], r.counts["false"], r.counts["sentence correct"]), (34, 10, 34))
        self.assertTrue(r.passed)
        preds["m50"] = {"need": "1"}
        self.assertFalse(marks.d1_mail(items, labels, preds).passed)

    def test_now_gate_for_an_unknown_sender(self):
        # Build spec 3.1: a stranger cannot make an alert with urgent words.
        self.assertEqual(marks.apply_when_gate(mail("m1"), "now", False), "list")
        self.assertEqual(marks.apply_when_gate(mail("m1"), "now", True), "now")
        self.assertEqual(marks.apply_when_gate(mail("n1", kind="note"), "now", True), "list")

    def test_sender_known_from_an_earlier_mail(self):
        a, b = mail("m1"), mail("m2")
        for m in (a, b):
            del m["sender_known"]
        b["date"] = "2026-11-04T08:00:00Z"
        self.assertEqual(marks.sender_known([a, b]), {"m1": False, "m2": True})

    def test_pairs_propose_the_best_candidate_or_none(self):
        pairs = [{"id": f"p{i}", "a": {"kind": "capture", "text": f"text {i // 2}"}} for i in range(4)]
        labels = [{"id": "p0", "label": "1"}, {"id": "p1", "label": "0"}, {"id": "p2", "label": "0"},
                  {"id": "p3", "label": "0"}]
        r = marks.pairs_mark("fit", pairs, labels, {"p0": 0.9, "p1": 0.2, "p2": 0.3, "p3": 0.1}, 0.5)
        self.assertEqual((r.counts["proposals"], r.counts["correct"]), (1, 1))
        self.assertTrue(r.passed)


class SealedTests(unittest.TestCase):
    def test_sealed_run_checks_the_hash_and_runs_one_time(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            data = d / "S9.jsonl.gz"
            write_jsonl(data, [mail("m1")])
            write_tsv(label_file(data), NEED_LABEL_COLUMNS, [{"id": "m1", "need": "list",
                      "sentence": "Could you send the form by Friday?"}])
            sha = d / "S9.sha256"
            sha.write_text(f"{'0' * 64}  S9.jsonl.gz\n{bench.sha256(label_file(data))}  S9-labels.tsv\n")
            fake = lambda arm, items: {"m1": {"need": "1", "when": "list", "sentence": "Could you send the form by Friday?"}}
            with self.assertRaises(RuntimeError):
                bench.sealed_run("S9", data, sha, ["x"], runs_dir=d / "runs", predict=fake)
            sha.write_text(f"{bench.sha256(data)}  S9.jsonl.gz\n{bench.sha256(label_file(data))}  S9-labels.tsv\n")
            out = bench.sealed_run("S9", data, sha, ["x"], runs_dir=d / "runs", predict=fake)
            self.assertIn("found 1", out)
            self.assertNotIn("Could you", out)
            with self.assertRaises(RuntimeError):
                bench.sealed_run("S9", data, sha, ["x"], runs_dir=d / "runs", predict=fake)


if __name__ == "__main__":
    unittest.main()
