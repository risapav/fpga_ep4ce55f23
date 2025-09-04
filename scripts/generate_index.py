"""
generate_index.py
-----------------
Načíta index.json (vygenerovaný extraktom zo .sv súborov) a
vytvorí index.md s tabuľkou modulov, pričom odkazy na moduly sú
upravené na .html, aby fungovali na GitHub Pages.

Tento skript predpokladá:
- index.json obsahuje: module, source, doc, brief
- docs_md/modules/... obsahuje .md súbory pre jednotlivé moduly
"""

import json
from pathlib import Path
import subprocess

# adresár s modulmi a index.json
modules_dir = Path("docs_md/modules")
index_file = Path("docs_md/index.md")
json_file = Path("docs_md/index.json")


def get_git_remote_url():
    """
    Získa URL repozitára z git configu a skonvertuje na https.
    Napr. git@github.com:user/repo.git -> https://github.com/user/repo
    """
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
    """
    Zistí aktuálnu vetvu (defaultne main).
    """
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"], encoding="utf-8"
        ).strip()
    except subprocess.CalledProcessError:
        return "main"


GITHUB_REPO_URL = get_git_remote_url()
BRANCH = get_git_branch()

# načítanie index.json
with open(json_file, encoding="utf-8") as f:
    modules = json.load(f)

# zoradenie modulov podľa mena
modules.sort(key=lambda m: m["module"].lower())

# generovanie index.md
with open(index_file, "w", encoding="utf-8") as f:
    f.write("# Dokumentácia modulov\n\n## 🔧 Zoznam\n\n")
    f.write("| Názov modulu | Popis | Zdrojový súbor |\n")
    f.write("|--------------|--------|----------------|\n")

    for m in modules:
        module_name = m["module"]
        brief = m["brief"] if m["brief"] else "-"

        # Odkaz na modul (.html namiesto .md pre GitHub Pages)
        html_doc_path = m["doc"].replace(".md", ".html")
        doc_link = f"[{module_name}]({html_doc_path})"

        # Relatívna cesta k zdrojovému súboru + link do GitHubu
        src_file = m["source"]
        src_url = f"{GITHUB_REPO_URL}/blob/{BRANCH}/src/{src_file}"
        src_link = f"[{src_file}]({src_url})"

        # zapíš riadok do tabuľky
        f.write(f"| {doc_link} | {brief} | {src_link} |\n")

print(f"📄 Aktualizovaný index s .html odkazmi: {index_file}")
