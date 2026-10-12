"""Prüft, ob Aufrufe wie services.X:Method() / ctx.X:Method() auf existierende Methoden zeigen."""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent / "src"
defs = {}
for path in root.rglob("*.luau"):
    name = path.name.split(".")[0]
    text = path.read_text(encoding="utf-8")
    methods = set(re.findall(r"function\s+\w+[:.](\w+)\s*\(", text))
    # Felder wie X.Signal = Signal.new()
    fields = set(re.findall(r"^\w+\.(\w+)\s*=", text, re.M)) | set(re.findall(r"self\.(\w+)\s*=", text))
    defs.setdefault(name, set()).update(methods | fields)

pattern = re.compile(r"(?:services|self\.Services|Services|ctx|self\.Ctx|ui\.Ctx|self\.UI\.Ctx)\.(\w+)[:.](\w+)")
errors = 0
for path in root.rglob("*.luau"):
    text = path.read_text(encoding="utf-8")
    for match in pattern.finditer(text):
        module, member = match.group(1), match.group(2)
        if module not in defs:
            continue
        if member not in defs[module]:
            line = text[: match.start()].count("\n") + 1
            print(f"{path.relative_to(root)}:{line}: {module}.{member} nicht gefunden")
            errors += 1
# Direkte Service-Variablen (local x = services.Name)
alias = re.compile(r"local\s+(\w+)\s*=\s*(?:self\.)?(?:services|Services|ctx|self\.Ctx)\.(\w+)\s*$", re.M)
for path in root.rglob("*.luau"):
    text = path.read_text(encoding="utf-8")
    for a in alias.finditer(text):
        var, module = a.group(1), a.group(2)
        if module not in defs:
            continue
        for m in re.finditer(r"\b" + re.escape(var) + r"[:.](\w+)", text):
            member = m.group(1)
            if member not in defs[module]:
                line = text[: m.start()].count("\n") + 1
                print(f"{path.relative_to(root)}:{line}: {var}({module}).{member} nicht gefunden")
                errors += 1
print(f"{errors} Problem(e)")
sys.exit(1 if errors else 0)
