import os
import subprocess

modules_dir = 'docs_md/modules'
index_file = 'docs_md/index.md'
src_dir = 'src'

def get_git_remote_url():
    try:
        url = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"], encoding='utf-8'
        ).strip()
        if url.startswith("git@github.com:"): url = url.replace("git@github.com:", "https://github.com/")
        if url.endswith(".git"): url = url[:-4]
        return url
    except subprocess.CalledProcessError:
        return None

def get_git_branch():
    try:
        branch = subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"], encoding='utf-8').strip()
        return branch
    except subprocess.CalledProcessError:
        return "main"

GITHUB_REPO_URL = get_git_remote_url() or "https://github.com/unknown/repo"
BRANCH = get_git_branch() or "main"

# Získanie všetkých markdown súborov vrátane podadresárov
md_files = []
for root, _, files in os.walk(modules_dir):
    for f in files:
        if f.endswith('.md'):
            md_files.append(os.path.join(root, f))
md_files.sort()

def extract_description(md_path):
    with open(md_path, encoding='utf-8') as f:
        content = f.read()
    import re
    m = re.search(r"## Popis\s*(.*?)\n\s*\n", content, re.DOTALL)
    if m:
        desc = m.group(1).strip().replace('\n', ' ')
        return desc[:117] + "..." if len(desc) > 120 else desc
    return "-"

def find_source_file(module_md_path):
    # Odhad cesty k .sv súboru podľa názvu modulu
    module_name = os.path.splitext(os.path.basename(module_md_path))[0]
    for root, _, files in os.walk(src_dir):
        for file in files:
            if file == module_name + '.sv':
                return os.path.relpath(os.path.join(root, file))
    return None

def generate_source_url(src_file):
    if not src_file: return "-"
    return f"{GITHUB_REPO_URL}/blob/{BRANCH}/{src_file.replace(os.sep, '/')}"

with open(index_file, 'w', encoding='utf-8') as f:
    f.write("# Dokumentácia modulov\n\n## 🔧 Zoznam\n\n")
    f.write("| Názov modulu | Popis | Zdrojový súbor |\n")
    f.write("|--------------|--------|----------------|\n")

    for md in md_files:
        module_name = os.path.splitext(os.path.basename(md))[0]
        desc = extract_description(md)
        src_file = find_source_file(md)
        md_link = f"[{module_name}]({os.path.relpath(md, modules_dir).replace(os.sep, '/')})"
        src_link = generate_source_url(src_file)
        src_link_md = f"[{os.path.basename(src_file)}]({src_link})" if src_file else "-"
        f.write(f"| {md_link} | {desc} | {src_link_md} |\n")

print(f"📄 Aktualizovaný index: {index_file}")
