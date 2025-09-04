import json
from pathlib import Path

modules_dir = Path("docs_md/modules")
readme_file = Path("docs_md/README.md")  # namiesto index.md
json_file = Path("docs_md/index.json")

# načítanie JSON indexu
with open(json_file, encoding="utf-8") as f:
    modules = json.load(f)

# zoradenie podľa mena
modules.sort(key=lambda m: m["module"].lower())

with open(readme_file, "w", encoding="utf-8") as f:
    f.write("# Dokumentácia modulov\n\n## 🔧 Zoznam\n\n")
    f.write("| Názov modulu | Popis | Zdrojový súbor |\n")
    f.write("|--------------|--------|----------------|\n")

    for m in modules:
        module_name = m["module"]
        brief = m["brief"] if m["brief"] else "-"
        html_doc = m["doc"].replace(".md", ".html")  # odkazy na HTML
        doc_link = f"[{module_name}]({html_doc})"
        src_file = m["source"]
        src_link = f"[{src_file}](https://github.com/<user>/<repo>/blob/main/src/{src_file})"  # uprav podľa repo
        f.write(f"| {doc_link} | {brief} | {src_link} |\n")

print(f"📄 Vygenerovaný README.md index: {readme_file}")
