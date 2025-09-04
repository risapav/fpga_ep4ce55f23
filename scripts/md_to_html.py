import markdown
from pathlib import Path

docs_dir = Path("docs_md")
modules_dir = docs_dir / "modules"

# všetky .md súbory vrátane README
md_files = list(modules_dir.rglob("*.md")) + [docs_dir / "README.md"]

for md_file in md_files:
    html_file = md_file.with_suffix(".html")
    text = md_file.read_text(encoding="utf-8")
    html_content = markdown.markdown(text, extensions=["tables", "fenced_code"])
    html_file.write_text(html_content, encoding="utf-8")
    print(f"✅ {md_file} -> {html_file}")
