"""
generate_index.py
-----------------
Generuje README.md index zo súboru index.json.
- Odkazy modulov smerujú na .html (po konverzii)
- Zachováva brief, zdrojový súbor a relatívnu cestu.
- Linky sú relatívne k README a zohľadňujú adresárovú štruktúru.
"""

import json
from pathlib import Path
import subprocess

# Adresáre
modules_dir = Path("docs_md/modules")
readme_file = Path("docs_md/README.md")
json_file = Path("docs_md/index.json")

def get_git_remote_url():
    """Získa URL GitHub repozitára"""
    try:
        url = subprocess.check_output(
            ["git","config","--get","remote.origin.url"],
            encoding="utf-8"
        ).strip()
        if url.startswith("git@github.com:"):
            url = url.replace("git@github.com:", "https://github.com/")
        if url.endswith(".git"):
            url = url[:-4]
        return url
    except subprocess.CalledProcessError:
        return None

def get_git_branch():
    """Získa aktuálnu vetvu repozitára"""
    try:
        branch = subprocess.check_output(
            ["git","rev-parse","--abbrev-ref","HEAD"],
            encoding="utf-8"
        ).strip()
        return branch
    except subprocess.CalledProcessError:
        return "main"

GITHUB_REPO_URL = get_git_remote_url() or "https://github.com/unknown/repo"
BRANCH = get_git_branch() or "main"

# Načítanie index.json
with open(json_file, encoding="utf-8") as f:
    modules = json.load(f)

# Zoradenie podľa mena modulu
modules.sort(key=lambda m: m["module"].lower())

with open(readme_file, "w", encoding="utf-8") as f:
    f.write("# Dokumentácia modulov\n\n## 🔧 Zoznam\n\n")
    f.write("| Názov modulu | Popis | Zdrojový súbor |\n")
    f.write("|--------------|--------|----------------|\n")

    for m in modules:
        module_name = m["module"]
        brief = m["brief"] or "-"
        # html_doc = relatívna cesta od modules_dir
        html_doc = m["doc"].replace(".md",".html")
        # Link relatívny k README
        doc_link = f"[{module_name}](modules/{html_doc})"
        src_file = m["source"]
        src_link = f"[{src_file}]({GITHUB_REPO_URL}/blob/{BRANCH}/src/{src_file})"
        f.write(f"| {doc_link} | {brief} | {src_link} |\n")

print(f"📄 Vygenerovaný README.md index: {readme_file}")
