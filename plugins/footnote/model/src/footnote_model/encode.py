"""The model input (build spec 4.1): `facts line [SEP] text A [SEP] text B`.

For an item (D1, D4), text A is the subject and the sentences of the prepared text. The Swift program prepares the
text (quoted, forwarded and signature parts cut) and makes the facts line, so that the fit and Footnote use the same
code. A mark token is at the start of each sentence: the sentence head reads it. A long item is cut into windows of
256 tokens or fewer on sentence borders. Each window has the facts line and the subject again.

For a pair (D2, D3), text A is the text and text B is the kind, the name and the records of the candidate.
"""

from __future__ import annotations

from dataclasses import dataclass, field

MAX_TOKENS = 256
SENTENCE_SEPARATOR = "\x1e"


@dataclass
class Window:
    item_id: str
    ids: list[int]
    starts: list[int] = field(default_factory=list)  # token index of the mark of each sentence
    sentences: list[str] = field(default_factory=list)


def item_windows(tok, item_id: str, facts: str, subject: str, sentences: list[str], max_tokens: int = MAX_TOKENS,
                 max_sentence: int = 80) -> list[Window]:
    cls, sep = tok.cls_token_id, tok.sep_token_id
    mark = mark_id(tok)
    head = [cls] + tok.encode(facts, add_special_tokens=False) + [sep] + tok.encode(subject, add_special_tokens=False)[:24] + [sep]
    room = max_tokens - len(head) - 1
    windows, cur = [], Window(item_id, list(head))
    for s in sentences:
        t = tok.encode(s, add_special_tokens=False)[:max_sentence]
        if len(cur.ids) + 1 + len(t) > len(head) + room and cur.sentences:
            cur.ids.append(sep)
            windows.append(cur)
            cur = Window(item_id, list(head))
        cur.starts.append(len(cur.ids))
        cur.sentences.append(s)
        cur.ids += [mark] + t
    cur.ids.append(sep)
    windows.append(cur)
    return windows


def mark_id(tok) -> int:
    """The mark token: an unused token of the word list if there is one, else the mask token."""
    for t in ("[unused1]", "<unused1>"):
        i = tok.convert_tokens_to_ids(t)
        if i is not None and i != tok.unk_token_id:
            return i
    return tok.mask_token_id


def pair_text_b(b: dict) -> str:
    recs = "; ".join(b.get("records", [])[:5])
    return f"{b['kind']}: {b['name']}" + (f" | {recs}" if recs else "")


def pair_ids(tok, owner: str, a: dict, b: dict, max_tokens: int = MAX_TOKENS) -> list[int]:
    cls, sep = tok.cls_token_id, tok.sep_token_id
    facts = tok.encode(f"owner: {owner} | a: {a['kind']} | b: {b['kind']}", add_special_tokens=False)
    tb = tok.encode(pair_text_b(b), add_special_tokens=False)[:96]
    room = max_tokens - len(facts) - len(tb) - 4
    ta = tok.encode(a["text"], add_special_tokens=False)[:max(room, 16)]
    return [cls] + facts + [sep] + ta + [sep] + tb + [sep]
