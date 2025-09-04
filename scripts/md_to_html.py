"""
md_to_html.py
-------------
Konvertuje Markdown súbory (README + modules/*.md) do kompletných HTML dokumentov
s CSS pre čitateľnosť, klikateľné odkazy a správne tabuľky.
"""

import markdown
from pathlib import Path

docs_dir = Path("docs_md")
modules_dir = docs_dir / "modules"

md_files = list(modules_dir.rglob("*.md")) + [docs_dir / "README.md"]

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="sk">
<head>
<meta charset="UTF-8">
<title>{title}</title>
<style>
body {{ font-family: sans-serif; margin: 2rem; }}
table {{ border-collapse: collapse; width: 100%; }}
th, td {{ border: 1px solid #ccc; padding: 0.5rem; }}
th {{ background: #f0f0f0; }}
a {{ color: #0366d6; text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
code {{ background-color: #f5f5f5; padding: 2px 4px; border-radius: 4px; }}
pre {{ background-color: #f5f5f5; padding: 1rem; overflow-x: auto; border-radius: 4px; }}
</style>
</head>
<body>
{content}
</body>
</html>"""

for md_file in md_files:
    md_text = md_file.read_text(encoding="utf-8")
    html_body = markdown.markdown(md_text, extensions=["tables","fenced_code","codehilite","toc"])
    page_title = md_file.stem
    html_content = HTML_TEMPLATE.format(title=page_title, content=html_body)
    html_file = md_file.with_suffix(".html")
    html_file.write_text(html_content, encoding="utf-8")
    print(f"✅ {md_file} -> {html_file}")
