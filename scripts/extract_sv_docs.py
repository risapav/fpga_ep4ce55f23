import re
from pathlib import Path

def parse_sv_file(filepath: Path):
    content = filepath.read_text(encoding='utf-8')

    # Nájdi všetky bloky /** ... */ pre každý modul
    doc_blocks = re.findall(r"/\*\*(.*?)\*/", content, re.DOTALL)

    # Nájdi všetky moduly v súbore
    module_matches = re.findall(r"\bmodule\s+(\w+)", content)
    if not module_matches:
        return {}

    md_outputs = {}

    for i, module_name in enumerate(module_matches):
        block = doc_blocks[i].strip() if i < len(doc_blocks) else ""
        brief = details = note = ""
        params, inputs, outputs, inouts = [], [], [], []
        code_blocks, example_blocks = [], []

        lines = [line.strip(" *") for line in block.splitlines()]
        current_tag = None
        current_text = []

        def flush_current():
            nonlocal current_tag, current_text, brief, details, note
            text = "\n".join(current_text).strip()
            if current_tag == "brief": brief = text
            elif current_tag == "details": details = text
            elif current_tag == "note": note = text
            elif current_tag == "param" and text:
                parts = text.split(None, 1)
                params.append((parts[0], parts[1] if len(parts) > 1 else ""))
            elif current_tag == "input" and text:
                parts = text.split(None, 1)
                inputs.append((parts[0], parts[1] if len(parts) > 1 else ""))
            elif current_tag == "output" and text:
                parts = text.split(None, 1)
                outputs.append((parts[0], parts[1] if len(parts) > 1 else ""))
            elif current_tag == "inout" and text:
                parts = text.split(None, 1)
                inouts.append((parts[0], parts[1] if len(parts) > 1 else ""))
            elif current_tag == "code" and text: code_blocks.append(text)
            elif current_tag == "example" and text: example_blocks.append(text)
            current_tag = None
            current_text = []

        for line in lines:
            for tag in ["brief", "details", "note", "param", "input", "output", "inout", "code", "example"]:
                if line.startswith(f"@{tag}"):
                    flush_current()
                    current_tag = tag
                    current_text.append(line[len(f"@{tag}"):].strip())
                    break
            else:
                if line.startswith("@endcode") or line.startswith("@endexample"):
                    flush_current()
                elif current_tag:
                    current_text.append(line)
        flush_current()

        md = f"# Modul `{module_name}`\n\n"
        if brief: md += f"## Popis\n\n{brief}\n\n"
        if details: md += f"{details}\n\n"
        if note: md += f"**Poznámka:** {note}\n\n"
        if params:
            md += "## Parametre\n\n" + "\n".join(f"- `{n}`: {d}" for n, d in params) + "\n\n"

        def gen_table(name, items):
            if not items: return ""
            table = f"## {name}\n\n| Názov | Popis |\n|-------|--------|\n"
            table += "\n".join(f"| `{n}` | {d} |" for n, d in items) + "\n\n"
            return table

        md += gen_table("Vstupy (input)", inputs)
        md += gen_table("Výstupy (output)", outputs)
        md += gen_table("Obojsmerné (inout)", inouts)

        if code_blocks:
            md += "## Príklady kódu\n\n" + "\n".join(f"```systemverilog\n{c}\n```" for c in code_blocks) + "\n\n"
        if example_blocks:
            md += "## Príklady použitia\n\n" + "\n".join(f"```systemverilog\n{e}\n```" for e in example_blocks) + "\n\n"

        md_outputs[module_name] = md

    return md_outputs


def main():
    src_dir = Path("./src")
    out_dir = Path("./docs_md/modules")
    out_dir.mkdir(parents=True, exist_ok=True)

    sv_files = list(src_dir.rglob("*.sv"))
    print(f"Načítavam {len(sv_files)} .sv súborov...")

    for sv_file in sv_files:
        md_dict = parse_sv_file(sv_file)
        for module_name, md in md_dict.items():
            # Zachovanie hierarchie adresárov
            rel_path = sv_file.relative_to(src_dir).with_name(module_name + ".md")
            md_file = out_dir / rel_path
            md_file.parent.mkdir(parents=True, exist_ok=True)
            md_file.write_text(md, encoding="utf-8")
            print(f"Vygenerovaný: {md_file}")


if __name__ == "__main__":
    main()
