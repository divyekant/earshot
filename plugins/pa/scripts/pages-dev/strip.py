# Takes the hand-written development pages of phase 4 (pages-dev/src/dNN.html, with label marks data-l="main" or
# data-l="neutral" on elements), writes each page without the marks to pages-dev/pages/, and writes the label file
# labels/dNN.tsv: one line "class<TAB>text" for each marked element. Text in no marked element is noise
# (spec section 7.2, RULE.md of the holdout). This script writes no page text of its own.
import html, html.parser, os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "Tests/PACoreTests/Fixtures/phase4/pages-dev"
src = os.path.join(root, "src")
os.makedirs(os.path.join(root, "pages"), exist_ok=True)
os.makedirs(os.path.join(root, "labels"), exist_ok=True)
VOID = {"meta", "br", "img", "input", "hr", "link", "source", "wbr"}
INLINE = {"a", "b", "i", "em", "strong", "span", "code", "sup", "sub", "small", "abbr"}

class Labels(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []  # (tag, index of the label or None)
        self.out = []    # [class, [parts], tag]
    def gap(self, tag):
        # A block tag inside a marked element separates words ("<td>Built</td><td>1861</td>").
        if tag not in INLINE:
            for _, idx in reversed(self.stack):
                if idx is not None:
                    self.out[idx][1].append(" ")
                    return
    def handle_starttag(self, tag, attrs):
        self.gap(tag)
        if tag in VOID:
            return
        cls = dict(attrs).get("data-l")
        idx = None
        if cls:
            self.out.append([cls, [], tag])
            idx = len(self.out) - 1
        self.stack.append((tag, idx))
    def handle_endtag(self, tag):
        self.gap(tag)
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                del self.stack[i:]
                break
    def handle_data(self, data):
        for tag, idx in reversed(self.stack):
            if idx is not None:
                self.out[idx][1].append(data)
                return

for name in sorted(os.listdir(src)):
    if not name.endswith(".html"):
        continue
    text = open(os.path.join(src, name), encoding="utf-8").read()
    p = Labels()
    p.feed(text)
    lines = []
    for cls, parts, tag in p.out:
        raw = "".join(parts)
        chunks = raw.split("\n") if tag == "textarea" else [raw]
        for c in chunks:
            t = re.sub(r"\s+", " ", c).strip()
            if t:
                lines.append(f"{cls}\t{t}")
    stem = name[:-5]
    with open(os.path.join(root, "labels", stem + ".tsv"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    clean = re.sub(r' data-l="(main|neutral)"', "", text)
    with open(os.path.join(root, "pages", name), "w", encoding="utf-8") as f:
        f.write(clean)
    print(stem, len(lines), "lines")
