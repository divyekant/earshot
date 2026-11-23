"""E13 L1: no command of `fm local-check` prints a field of a mail (spec 2.2). Made-up mail only."""

import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from footnote_model import cli, local_check
from footnote_model.formats import write_jsonl

SECRET = ("Quokka", "zephyr.vane", "Marigold-77", "l1-00")


def mail(n, list_header=False):
    return {"id": f"l1-{n:04d}", "kind": "mail", "owner": {"name": "ana lim", "address": "ana.lim@example.com"},
            "now": "2026-11-23T08:00:00Z", "from_name": f"Quokka Person {n}",
            "from_address": f"zephyr.vane{n}@example.org", "to": ["ana.lim@example.com"], "cc": [],
            "subject": f"Marigold-77 plan {n}", "date": f"2026-11-{10 + n % 10:02d}T08:00:00Z",
            "list_unsubscribe": list_header, "precedence": "", "auto_submitted": False, "junk": False,
            "replied": False, "body": f"Could you check the Marigold-77 form, Quokka? {n}"}


class LocalCheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        write_jsonl(self.d / local_check.EXPORT, [mail(n, list_header=n % 7 == 0) for n in range(1, 61)])
        self.cfg_path = self.d.parent / f"cfg-{os.getpid()}.json"
        cfg = local_check.load_config()
        self.cfg_path.write_text(json.dumps(cfg))
        self.cfg = cfg

    def tearDown(self):
        self.tmp.cleanup()
        self.cfg_path.unlink(missing_ok=True)

    def run_cli(self, step):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli.main(["local-check", step, "--dir", str(self.d), "--config", str(self.cfg_path), "--no-open"])
        return rc, buf.getvalue()

    def score(self):
        def rules(d, items):
            return {it["id"]: {"need": "1" if int(it["id"][-2:]) % 3 == 0 else "0",
                               "gate": "greets another" if int(it["id"][-2:]) % 5 == 0 else ""} for it in items}

        def model(k):
            return lambda items, sw: {it["id"]: {"p_req": (int(it["id"][-2:]) * (k + 3) % 10) / 10, "p_now": 0.5}
                                      for it in items}
        local_check.score(self.d, self.cfg, rules=rules, models=[model(0), model(1), model(2)])

    def assert_clean(self, text):
        for s in SECRET:
            self.assertNotIn(s, text)

    def test_no_command_prints_a_field_of_a_mail(self):
        self.score()
        self.assertEqual(oct(os.stat(self.d / local_check.SCORES).st_mode & 0o777), "0o600")
        rc, out = self.run_cli("counts")
        self.assertEqual(rc, 0)
        self.assertIn("Mails read: 60", out)
        self.assertIn("list header 8", out)
        self.assert_clean(out)
        n = local_check.make_list(self.d, self.cfg)
        self.assertLessEqual(n, 45)
        page = (self.d / local_check.LIST).read_text()
        # The page shows the mails, not the groups or the arms.
        self.assertIn("Marigold-77", page)
        for word in ("model only", "rules only", "both"):
            self.assertNotIn(word, page)
        with self.assertRaises(RuntimeError):
            local_check.make_list(self.d, self.cfg)
        (self.d / local_check.MARKS).write_text(json.dumps({"1": "needed", "2": "not needed"}))
        rc, out = self.run_cli("marks")
        self.assert_clean(out)
        self.assertIn("needed me", out)
        rc, out = self.run_cli("clean")
        self.assert_clean(out)
        left = sorted(p.name for p in self.d.iterdir())
        self.assertEqual(left, [local_check.SUMMARY])
        summary = (self.d / local_check.SUMMARY).read_text()
        self.assert_clean(summary)
        rc, out = self.run_cli("marks")
        self.assertIn("needed me 1", out.replace("did not need me 1", ""))

    def test_sample_is_fixed_by_the_seed(self):
        self.score()
        rows = local_check.read_scores(self.d)
        self.assertEqual(local_check.sample(rows, self.cfg), local_check.sample(rows, self.cfg))

    def test_a_wrong_model_file_stops_the_score(self):
        cfg = dict(self.cfg, model_root=str(self.d))
        (self.d / "s13").mkdir()
        (self.d / "s13" / "model.pt").write_bytes(b"not the model")
        with self.assertRaises(RuntimeError):
            local_check.score(self.d, cfg, rules=lambda d, items: {})


if __name__ == "__main__":
    unittest.main()
