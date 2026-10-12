"""Erzeugt aus default.project.json eine Luau-Tabelle mit dem Instanzbaum (für Mock-Tests)."""
import json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def from_path(path: pathlib.Path, name: str):
    if path.is_file():
        base = path.name
        if base.endswith(".server.luau"):
            cls = "Script"
        elif base.endswith(".client.luau"):
            cls = "LocalScript"
        else:
            cls = "ModuleScript"
        return {"Class": cls, "Name": name, "Source": str(path), "Children": []}
    children = []
    for entry in sorted(path.iterdir()):
        if entry.is_dir():
            children.append(from_path(entry, entry.name))
        elif entry.suffix == ".luau":
            children.append(from_path(entry, entry.name.split(".")[0]))
    return {"Class": "Folder", "Name": name, "Children": children}

def node(name, data):
    if "$path" in data:
        result = from_path(ROOT / data["$path"], name)
        if "$className" in data:
            result["Class"] = data["$className"]
    else:
        result = {"Class": data.get("$className", "Folder"), "Name": name, "Children": []}
    result["Props"] = data.get("$properties", {})
    for key, value in data.items():
        if not key.startswith("$"):
            result["Children"].append(node(key, value))
    return result

def emit(n, indent=""):
    parts = [f'{indent}{{ Class = {lua_str(n["Class"])}, Name = {lua_str(n["Name"])}']
    if "Source" in n:
        parts.append(f', Source = {lua_str(n["Source"])}')
    props = n.get("Props", {})
    if props:
        items = []
        for k, v in props.items():
            if isinstance(v, bool):
                items.append(f"{k} = {'true' if v else 'false'}")
            elif isinstance(v, (int, float)):
                items.append(f"{k} = {v}")
            elif isinstance(v, str):
                items.append(f"{k} = {lua_str(v)}")
        parts.append(", Props = { " + ", ".join(items) + " }")
    parts.append(", Children = {\n")
    for child in n.get("Children", []):
        parts.append(emit(child, indent + "  ") + ",\n")
    parts.append(f"{indent}}} }}")
    return "".join(parts)

project_file = sys.argv[2] if len(sys.argv) > 2 else "default.project.json"
project = json.loads((ROOT / project_file).read_text())
root_class = project["tree"].get("$className", "Folder")
tree = node("game" if root_class == "DataModel" else project["name"], project["tree"])
out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tools/test/_tree.luau"
out.write_text("return " + emit(tree) + "\n")
print("tree written to", out)
