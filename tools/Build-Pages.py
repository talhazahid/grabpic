"""Render the canonical Markdown privacy policy for the static GitHub Pages site."""
from pathlib import Path
import html
import re

root = Path(__file__).resolve().parents[1]
source = (root / "docs/PRIVACY.md").read_text(encoding="utf-8-sig")

def inline(text):
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\[([^\]]+)\]\((https://[^)]+)\)", r'<a href="\2">\1</a>', text)
    return text

parts = []
for block in source.strip().split("\n\n"):
    block = block.strip()
    if block.startswith("## "):
        parts.append(f"<h2>{inline(block[3:])}</h2>")
    elif block.startswith("# "):
        parts.append(f"<h1>{inline(block[2:])}</h1>")
    else:
        parts.append(f"<p>{inline(block.replace(chr(10), ' '))}</p>")

page = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="How Grabpic handles screenshots, clipboard images, shortcuts, and local preferences.">
<meta name="theme-color" content="#14151b"><title>Privacy policy — Grabpic</title>
<link rel="canonical" href="https://talhazahid.github.io/grabpic/privacy/">
<link rel="icon" type="image/png" href="../images/icon.png"><link rel="stylesheet" href="../site.css"></head>
<body><a class="skip" href="#main">Skip to content</a><div class="container">
<header class="header"><a class="brand" href="../"><img src="../images/icon.png" width="42" height="42" alt=""><span>Grabpic</span></a>
<nav class="nav" aria-label="Main navigation"><a href="../">Home</a><a href="https://github.com/talhazahid/grabpic">GitHub ↗</a></nav></header>
<main class="prose" id="main">BODY</main>
<footer class="footer"><span>Grabpic · Owl Dev · GPL-3.0</span><span><a href="../">Home</a> &nbsp;·&nbsp; <a href="https://github.com/talhazahid/grabpic/issues">Support</a></span></footer>
</div></body></html>
'''.replace("BODY", "\n".join(parts))
target = root / "docs/privacy/index.html"
target.parent.mkdir(exist_ok=True)
target.write_text(page, encoding="utf-8")
assert "Clipboard monitoring is optional" in page
assert "does not maintain a typing history" in page
print("Built privacy page from docs/PRIVACY.md")
