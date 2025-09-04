"""
generate_index.py
-----------------
Načíta index.json (vygenerovaný extraktom zo .sv súborov) a
vytvorí index.md s tabuľkou modulov.
"""

import json
from pathlib import Path
import subprocess

modules_dir = Path("docs_md/modules")
index_file = Path("docs_md/index.md")
json_file = Path("docs_md/index.json")


def get_git_remote_url():
    """Zistí URL repozitára z git configu a skonvertuje na https."""
    try:
        url = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"], encoding="utf-8"
        ).strip()
        if url.startswith("git@github.com:"):
            url = url.replace("git@github.com:", "https://github.com/")
        if url.endswith(".git"):
            url = url[:-4]
        return url
    except subprocess.CalledProcessError:
        return "https://github.com/unknown/repo"


def get_git_branch():
    """Zistí aktuálnu vetvu (defaultne main)."""
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"], encoding="utf-8"
        ).strip()
    except subprocess.CalledProcessError:
        return "main"


GITHUB_REPO_URL = get_git_remote_url()
BRANCH = get_git_branch()

# načítaj JSON index
with open(json_file, encoding="utf-8") as f:
    modules = json.load(f)

# zoradenie podľa mena modulu
modules.sort(key=lambda m: m["module"].lower())

with open(index_file, "w", encoding="utf-8") as f:
    f.write("# Dokumentácia modulov\n\n## 🔧 Zoznam\n\n")
    f.write("| Názov modulu | Popis | Zdrojový súbor |\n")
    f.write("|--------------|--------|----------------|\n")

    for m in modules:
        module_name = m["module"]
        brief = m["brief"] if m["brief"] else "-"
        doc_link = f"[{module_name}]({m['doc']})"
        src_file = m["source"]
        src_url = f"{GITHUB_REPO_URL}/blob/{BRANCH}/src/{src_file}"
        src_link = f"[{src_file}]({src_url})"
        f.write(f"| {doc_link} | {brief} | {src_link} |\n")

print(f"📄 Aktualizovaný index: {index_file}")
