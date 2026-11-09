#!/usr/bin/env python3
"""R14: builds api-index.json from PaseoCore's symbol graphs (public API) plus the
PaseoUI/App source trees (internal declarations, for existence checking).

Usage:  python3 build_index.py <path to Packages/PaseoCore> <repo root>
Output: api-index.json next to this script.
"""
import json, re, sys, os, glob, collections

core = sys.argv[1]
root = sys.argv[2]
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "api-index.json")

graph_dir = os.path.join(core, ".build", "out", "symbolgraph")
modules = ["PaseoProtocol", "PaseoKit", "PaseoStore"]

def heading(s):
    return "".join(f.get("spelling") or "" for f in (s.get("names") or {}).get("subHeading") or [])


def member_type_spelling(heading_text, is_init, pc):
    """The declared type (property) or return type (method) as spelled in the heading."""
    if is_init:
        return pc[0] if pc else None
    arrow = re.search(r"->\s*", heading_text)
    if arrow:
        return heading_text[arrow.end():].strip() or None
    # property: text after the first top-level ": " following the identifier
    m = re.match(r"^(?:static\s+|class\s+)?(?:let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*", heading_text)
    if m:
        return heading_text[m.end():].strip() or None
    return None


def base_type_name(spelling):
    if not spelling: return None
    s = spelling.strip()
    if s.startswith("["): return "Dictionary" if has_top_level_colon(s) else "Array"
    if s.endswith("?") or s.endswith("!"): return "Optional"
    if s.startswith("Set<"): return "Set"
    if s.startswith("Dictionary<"): return "Dictionary"
    m = re.match(r"^(?:any|some)?\s*([A-Za-z_][A-Za-z0-9_]*)", s)
    return m.group(1) if m else None

def has_top_level_colon(s):
    depth = 0
    for ch in s:
        if ch in "<([": depth += 1
        elif ch in ">)]": depth -= 1
        elif ch == ":" and depth == 0: return True
    return False

def split_args(text):
    """Split a parameter list at top-level commas."""
    parts, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([<{": depth += 1; cur += ch
        elif ch in ")]}>": depth -= 1; cur += ch
        elif ch == "," and depth == 0: parts.append(cur); cur = ""
        else: cur += ch
    if cur.strip(): parts.append(cur)
    return [p.strip() for p in parts]

def param_labels(heading_text):
    """Labels in call order from 'func name(a: T, b: U) -> R' / 'init(a: T)'."""
    m = re.search(r"\(", heading_text)
    if not m: return []
    depth, end = 0, None
    for i, ch in enumerate(heading_text[m.start():], m.start()):
        if ch == "(": depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is None: return []
    inside = heading_text[m.start() + 1:end]
    if not inside.strip(): return []
    labels = []
    for clause in split_args(inside):
        clause = clause.strip()
        if not clause: continue
        cm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*|_)\s*:", clause)
        if cm:
            labels.append(cm.group(1))
        else:
            labels.append("_")
    return labels

seen_global = set()
index = {
    "types": {},          # name -> {module, kind}
    "members": collections.defaultdict(list),   # TypeName -> [member]
    "enumCases": collections.defaultdict(list), # TypeName -> [case]
    "freeFuncs": [],      # public free functions (none expected in PaseoCore)
}

for mod in modules:
    path = os.path.join(graph_dir, f"{mod}.symbols.json")
    d = json.load(open(path))
    seen = seen_global
    for s in d["symbols"]:
        sig = (tuple(s.get("pathComponents") or []), s.get("kind", {}).get("identifier"), heading(s))
        if sig in seen:
            continue
        seen.add(sig)
        kind = s.get("kind", {}).get("identifier")
        pc = s.get("pathComponents") or []
        if not pc: continue
        if kind in ("swift.struct", "swift.enum", "swift.class", "swift.actor", "swift.protocol", "swift.typealias"):
            index["types"][pc[-1]] = {"module": mod, "kind": kind}
        elif kind == "swift.enum.case":
            full = pc[-1]
            bare = re.sub(r"\(.*\)$", "", full)
            index["enumCases"][pc[0]].append(bare)
        elif kind in ("swift.func.op",):
            continue
        else:
            parent = pc[0] if len(pc) >= 1 else None
            name = pc[-1]
            is_static = kind.startswith("swift.type.")
            is_init = kind == "swift.init"
            heading_text = heading(s)
            m = {
                "name": name, "kind": kind, "isStatic": is_static,
                "labels": param_labels(heading_text) if (is_init or kind.startswith("swift.method") or kind.startswith("swift.type.method")) else None,
                "type": member_type_spelling(heading_text, is_init, pc),
                "file": (s.get("docComment") or {}).get("uri"),
                "line": ((s.get("docComment") or {}).get("lines") or [{}])[0].get("range", {}).get("start", {}).get("line"),
            }
            index["members"][parent].append(m)

# --- default parameter values from the PaseoCore sources (for init label checks) ---
core_src = glob.glob(os.path.join(core, "Sources", "**", "*.swift"), recursive=True)
type_scopes = []  # (start, end, name, file)
init_pos = []     # (pos, file)
enum_case_iterable = {}
for f in core_src:
    src = open(f).read()
    for m in re.finditer(r"(?:public\s+|open\s+|internal\s+|fileprivate\s+|private\s+)?(?:final\s+)?(?:struct|enum|class|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)", src):
        j = src.find("{", m.end())
        if j == -1:
            continue
        depth, k = 0, j
        while k < len(src):
            if src[k] == "{": depth += 1
            elif src[k] == "}":
                depth -= 1
                if depth == 0: break
            k += 1
        type_scopes.append((m.start(), k + 1, m.group(1), f))
        header = src[max(0, m.start() - 60):j]
        if "CaseIterable" in header and m.start() >= 0 and re.match(r"(?:public\s+|open\s+|internal\s+|fileprivate\s+|private\s+)?(?:final\s+)?enum", src[m.start():m.start() + 80]):
            enum_case_iterable[m.group(1)] = True
for name in enum_case_iterable:
    index["members"][name].append({"name": "allCases", "kind": "swift.type.property", "isStatic": True, "labels": None, "type": None, "file": None, "line": None})
for f in core_src:
    src = open(f).read()
    for m in re.finditer(r"\b(?:public\s+|open\s+|internal\s+|fileprivate\s+|private\s+)?(?:convenience\s+)?init\s*\(", src):
        init_pos.append((m.start(), f))

def enclosing_type(f, pos):
    best = None
    for start, end, name, tf in type_scopes:
        if tf == f and start <= pos < end:
            width = end - start
            if best is None or width < best[0]:
                best = (width, name)
    return best[1] if best else None

# match inits to symbol-graph entries by (parentType, arity) and record defaults
for (pos, f) in init_pos:
    t = enclosing_type(f, pos)
    if not t: continue
    src = open(f).read()
    # find the parameter list of this init by paren balancing from pos
    mp = src.find("(", pos)
    depth, i = 0, mp
    for j in range(mp, len(src)):
        if src[j] == "(": depth += 1
        elif src[j] == ")":
            depth -= 1
            if depth == 0: i = j; break
    inside = src[mp + 1:i]
    clauses = split_args(inside)
    labels, defaults = [], {}
    for clause in clauses:
        cm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*|_)\s*:", clause)
        if cm: labels.append(cm.group(1))
        else: labels.append("_")
        defaults[labels[-1]] = "=" in clause
    # attach to the first init entry of this type with the same arity & labels lacking info
    for m in index["members"][t]:
        if m["kind"] == "swift.init" and len(m["labels"]) == len(labels):
            if m.get("defaults") is None:
                m["defaults"] = defaults

# --- PaseoUI / App declarations (any access level) for internal existence checks ---
ui_root = os.path.join(root, "Packages", "PaseoUI", "Sources")
app_root = os.path.join(root, "App", "Sources")
local_types = {}          # name -> file
local_members = collections.defaultdict(list)   # TypeName -> [ {name, kind} ]
local_extension_members = collections.defaultdict(list)  # CoreTypeName -> [member names]
local_free_funcs = []     # names of top-level funcs
local_files = {}          # type name -> file (for private/fileprivate cross-file flags)

def strip_source(src):
    out, i = [], 0
    n = len(src)
    while i < n:
        # raw string
        if src[i] == "#" and src[i+1:i+2] == '"':
            j = i + 2
            while j < n and not (src[j] == '"' and src[j+1:j+2] == "#"):
                if src[j] == "\n": out.append("\n")
                else: out.append(" ")
                j += 1
            out.append("  "); i = j + 2 if j < n else n
            continue
        # multiline string
        if src[i:i+3] == '"""':
            j = src.find('"""', i + 3)
            if j == -1: j = n
            else: j += 3
            for ch in src[i:j]:
                out.append("\n" if ch == "\n" else " ")
            i = j
            continue
        # single line string
        if src[i] == '"':
            out.append('"'); i += 1
            while i < n:
                ch = src[i]
                if ch == "\\":
                    out.append("  "); i += 2; continue
                if ch == '"':
                    out.append('"'); i += 1; break
                out.append("\n" if ch == "\n" else " "); i += 1
            continue
        # block comment (nested)
        two = src[i:i+2]
        if two == "/*":
            depth, j = 0, i
            while j < n:
                if src[j:j+2] == "/*": depth += 1; out.append("  "); j += 2; continue
                if src[j:j+2] == "*/": depth -= 1; out.append("  "); j += 2
                if depth == 0: break
                if src[j] == "\n": out.append("\n"); j += 1; continue
                out.append(" "); j += 1
            i = j
            continue
        # line comment
        if two == "//":
            j = src.find("\n", i)
            if j == -1: j = n
            out.append(" " * (j - i))
            i = j
            continue
        out.append(src[i]); i += 1
    return "".join(out)

pat_type = re.compile(r"(?:public\s+|open\s+|internal\s+|fileprivate\s+|private\s+)?(?:final\s+)?(?:@MainActor\s+)?(?:struct|enum|class|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)")
pat_func = re.compile(r"\b((?:@?\w+\s+)*)(?:static\s+|class\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)")
pat_var  = re.compile(r"\b((?:static\s+|class\s+)?(?:var|let))\s+([A-Za-z_][A-Za-z0-9_]*)")

top_level_type_decls = []  # (name, file) for declarations at brace depth 0

def brace_depth_at(text, pos):
    depth = 0
    for i in range(pos):
        if text[i] == "{": depth += 1
        elif text[i] == "}": depth -= 1
    return depth

for f in glob.glob(os.path.join(ui_root, "**", "*.swift"), recursive=True) + glob.glob(os.path.join(app_root, "**", "*.swift"), recursive=True):
    raw = open(f).read()
    src = strip_source(raw)
    # top-level declarations only (column 0 or after leading whitespace, since extensions nest them)
    enum_scopes = {}
    for m in pat_type.finditer(src):
        name = m.group(1)
        if brace_depth_at(src, m.start()) == 0:
            top_level_type_decls.append((name, f))
        km = re.match(r"(?:public\s+|open\s+|internal\s+|fileprivate\s+|private\s+)?(?:final\s+)?(struct|enum|class|actor|protocol)", src[m.start():m.start() + 120])
        local_types[name] = {"file": f, "kind": km.group(1) if km else "type"}
        kind_match = re.match(r"(?:@?\w+\s+)*(?:public\s+|open\s+|internal\s+|fileprivate\s+|private\s+)?(?:final\s+)?(struct|enum|class|actor|protocol)", src[m.start():m.start() + 120])
        if kind_match and kind_match.group(1) == "enum":
            j = src.find("{", m.end())
            if j != -1:
                header = src[max(0, m.start() - 40):j]
                enum_scopes[name] = ("CaseIterable" in header, m.start(), j)
        # find members inside braces: simple brace match from the type start
        depth, j = 0, src.find("{", m.end())
        if j == -1: continue
        k = j
        while k < len(src):
            if src[k] == "{": depth += 1
            elif src[k] == "}":
                depth -= 1
                if depth == 0: break
            k += 1
        body = src[j:k]
        for fm in pat_func.finditer(body):
            static = bool(re.search(r"static\s+|class\s+", fm.group(0)))
            local_members[name].append({"name": fm.group(2), "kind": "func", "isStatic": static})
        for vm in pat_var.finditer(body):
            static = bool(re.search(r"static\s+|class\s+", vm.group(1)))
            local_members[name].append({"name": vm.group(2), "kind": "var", "isStatic": static})
    for name, (case_iterable, start, j) in enum_scopes.items():
        if case_iterable:
            local_members[name].append({"name": "allCases", "kind": "var", "isStatic": True})
        # raw-representable enums get the synthesized rawValue + init(rawValue:)
        header = src[max(0, start - 200):j]
        if re.search(r":\s*(String|Int|Double|Float)\b", header):
            local_members[name].append({"name": "rawValue", "kind": "var", "isStatic": False})
            local_members[name].append({"name": "init(rawValue:)", "kind": "init", "labels": ["rawValue"], "isStatic": False})
        # cases are pseudo-static members: `.someCase` accesses
        body = src[j:]
        depth, k = 0, 0
        while k < len(body):
            if body[k] == "{": depth += 1
            elif body[k] == "}":
                depth -= 1
                if depth == 0: break
            k += 1
        case_marks = list(re.finditer(r"\bcase\s+", body[:k]))
        for i, cm in enumerate(case_marks):
            seg_end = case_marks[i + 1].start() if i + 1 < len(case_marks) else k
            seg = body[cm.end():seg_end]
            # the case declaration ends at the next declaration keyword
            seg = re.split(r"\b(?:func|var|let|static|nonisolated|public|private|internal|fileprivate|open|convenience|override|required|deinit)\b", seg, maxsplit=1)[0]
            for clause in split_args(seg):
                ident = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)", clause)
                if ident:
                    local_members[name].append({"name": ident.group(1), "kind": "case", "isStatic": True})
    for m in re.finditer(r"^\s*extension\s+([A-Za-z_][A-Za-z0-9_.]*)", src, re.M):
        target = m.group(1).split(".")[-1]
        depth, j = 0, src.find("{", m.end())
        if j == -1: continue
        k = j
        while k < len(src):
            if src[k] == "{": depth += 1
            elif src[k] == "}":
                depth -= 1
                if depth == 0: break
            k += 1
        body = src[j:k]
        for fm in pat_func.finditer(body):
            static = bool(re.search(r"static\s+|class\s+", fm.group(0)))
            local_extension_members[target].append({"name": fm.group(2), "kind": "func", "isStatic": static})
        for vm in pat_var.finditer(body):
            static = bool(re.search(r"static\s+|class\s+", vm.group(1)))
            local_extension_members[target].append({"name": vm.group(2), "kind": "var", "isStatic": static})
    for m in re.finditer(r"^func\s+([A-Za-z_][A-Za-z0-9_]*)", src, re.M):
        local_free_funcs.append(m.group(1))

# --- opaque local classes: inheritance clause mentions an unresolvable (framework) base ---
BUILTIN_CONFORMANCES = {
    "Sendable", "Hashable", "Equatable", "Comparable", "Identifiable", "Codable", "Encodable",
    "Decodable", "CaseIterable", "RawRepresentable", "OptionSet", "AnyObject", "Error",
    "Collection", "Sequence", "RandomAccessCollection", "BidirectionalCollection",
    "RangeReplaceableCollection", "LazySequence",
    "CustomStringConvertible", "CustomDebugStringConvertible", "CustomReflectable",
    "ExpressibleByStringLiteral", "ExpressibleByIntegerLiteral", "ExpressibleByFloatLiteral",
    "ExpressibleByBooleanLiteral", "ExpressibleByArrayLiteral", "ExpressibleByDictionaryLiteral",
    "ExpressibleByNilLiteral", "ExpressibleByUnicodeScalarLiteral",
    "ExpressibleByExtendedGraphemeClusterLiteral", "CodingKey", "Animatable", "View",
}
pat_class = re.compile(
    r"(?:public\s+|open\s+|internal\s+|fileprivate\s+|private\s+)?(?:final\s+)?(?:nonisolated\s+)?(?:class|struct)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>{]*>)?\s*(?::\s*([^{]+))?\{")
local_opaque = set()
for f in glob.glob(os.path.join(ui_root, "**", "*.swift"), recursive=True) + glob.glob(os.path.join(app_root, "**", "*.swift"), recursive=True):
    src = strip_source(open(f).read())
    for m in pat_class.finditer(src):
        name = m.group(1)
        clause = m.group(2) or ""
        for clause_part in split_args(clause):
            bm = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)", clause_part)
            if not bm:
                continue
            bn = bm.group(1)
            if bn in BUILTIN_CONFORMANCES:
                continue
            if bn in index["types"] or bn in local_types:
                continue
            local_opaque.add(name)
            break

# local extension members are used as-is by the checker (it merges core + local + ext)
ext_merged = dict(local_extension_members)

index["local_types"] = local_types
index["local_members"] = {t: ms for t, ms in local_members.items()}
index["local_extension_members"] = ext_merged
index["local_free_funcs"] = local_free_funcs
index["local_opaque"] = sorted(local_opaque)

# top-level type names declared in more than one place (a compile error within one file,
# a resolution ambiguity across files)
dup_by_name = collections.defaultdict(list)
for n, ff in top_level_type_decls:
    dup_by_name[n].append(ff)
index["duplicate_types"] = {n: sorted(fs) for n, fs in dup_by_name.items() if len(fs) > 1}

# unqualified function calls and their return types (single candidate only),
# used to infer `let x = f(...)` bindings
local_func_returns = {}
for f in glob.glob(os.path.join(ui_root, "**", "*.swift"), recursive=True) + glob.glob(os.path.join(app_root, "**", "*.swift"), recursive=True):
    src = strip_source(open(f).read())
    for m in re.finditer(r"\b(?:public\s+|open\s+|internal\s+|fileprivate\s+|private\s+)?(?:static\s+|class\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)", src):
        body_start = src.find("{", m.start())
        if body_start == -1:
            continue
        sig = src[m.start():body_start]
        arrow = re.search(r"->\s*([^\n{]+)", sig)
        if not arrow:
            continue
        raw = arrow.group(1).strip()
        if base_type_name(raw):
            local_func_returns.setdefault(m.group(1), set()).add(raw)
index["local_func_returns"] = {k: sorted(v) for k, v in local_func_returns.items() if len(v) == 1}

with open(out, "w") as fh:
    json.dump(index, fh, indent=0, sort_keys=False)
print(f"wrote {out}")
print("types:", len(index["types"]), "| member lists:", len(index["members"]),
      "| local types:", len(local_types), "| local files:", len(set(v["file"] for v in local_types.values())))
