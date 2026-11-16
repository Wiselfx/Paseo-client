#!/usr/bin/env python3
"""R14: audits PaseoUI/App sources against PaseoCore's public API and PaseoUI's own
declarations.  The point is to catch the Xcode compile errors that `swiftc -parse`
cannot: missing members, wrong argument labels, nonexistent enum cases.

Usage:  python3 check.py <repo root>   (after build_index.py)
"""
import json, re, sys, os, glob, collections

root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
index = json.load(open(os.path.join(here, "api-index.json")))
core_types = index["types"]                    # Core public types: name -> {module, kind}
local_types = index["local_types"]             # PaseoUI/App types: name -> file
members = index["members"]                     # Type -> [member]
local_members = index["local_members"]         # Type -> [member]
local_ext = index["local_extension_members"]   # Type -> [member]  (PaseoUI extensions of any type)
local_opaque = set(index.get("local_opaque", []))  # local classes with framework bases
enum_cases = index["enumCases"]                # Type -> [caseName]
local_free = set(index["local_free_funcs"])
local_members_map = {}
for t, ms in local_members.items():
    local_members_map[t] = ms

UI = glob.glob(os.path.join(root, "Packages", "PaseoUI", "Sources", "**", "*.swift"), recursive=True)
APP = glob.glob(os.path.join(root, "App", "Sources", "**", "*.swift"), recursive=True)
files = UI + APP

# ---------------- source preparation ----------------

def strip_source(src):
    """Replace comments and string-literal contents with spaces; keep newlines."""
    out, i = [], 0
    n = len(src)
    while i < n:
        two = src[i:i+2]
        # import line
        if src[i:i+7] == "import ":
            j = src.find("\n", i)
            if j == -1: j = n
            out.append(" " * (j - i)); i = j
            continue
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

# ---------------- type helpers ----------------

GENERICS_STOP = set()

def base_type_name(spelling):
    """Maps declared types to a checkable base name; collections/optionals become sentinels."""
    if not spelling: return None
    s = spelling.strip()
    if s.startswith("["):
        return "Dictionary" if has_top_level_colon(s) else "Array"
    if s.endswith("?") or s.endswith("!"):
        return "Optional"
    if s.startswith("Set<"):
        return "Set"
    if s.startswith("Dictionary<"):
        return "Dictionary"
    m = re.match(r"^(?:any|some)?\s*([A-Za-z_][A-Za-z0-9_]*)", s)
    return m.group(1) if m else None

def has_top_level_colon(s):
    depth = 0
    for ch in s:
        if ch in "<([": depth += 1
        elif ch in ">)]": depth -= 1
        elif ch == ":" and depth == 0: return True
    return False

ARRAY_METHODS = {
    "allSatisfy","append","compactMap","compactMapValues","contains","count","dropFirst",
    "dropLast","enumerated","filter","first","firstIndex","flatMap","index","insert","isEmpty",
    "joined","last","lastIndex","map","max","min","prefix","reduce","remove","removeAll",
    "removeFirst","removeLast","sorted","split","suffix","swapAt","zip",
}

def split_args(text):
    parts, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([<{": depth += 1; cur += ch
        elif ch in ")]}>": depth -= 1; cur += ch
        elif ch == "," and depth == 0: parts.append(cur); cur = ""
        else: cur += ch
    if cur.strip(): parts.append(cur)
    return [p.strip() for p in parts]

def param_decls(f, src):
    """Function parameters as typed declarations: [(pos, name, baseType)]."""
    out = []
    for m in re.finditer(r"\bfunc\s+[A-Za-z_][A-Za-z0-9_]*\s*\(", src):
        pos_open = src.find("(", m.start())
        depth, i = 0, pos_open
        for j in range(pos_open, len(src)):
            if src[j] == "(": depth += 1
            elif src[j] == ")":
                depth -= 1
                if depth == 0: i = j; break
        inside = src[pos_open + 1:i]
        for clause in split_args(inside):
            clause = clause.strip()
            if not clause: continue
            two = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)$", clause)
            if two:
                label, type_text = two.group(2), two.group(3)
            else:
                pm = re.match(r"^_\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)$", clause)
                if not pm:
                    pm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*|_)\s*:\s*(.+)$", clause)
                if not pm: continue
                label, type_text = pm.group(1), pm.group(2)
            if label == "_": continue
            if re.match(r"^(?:inout|escaping|Optional<|sending|borrowing|consuming|autoclosure|rethrows)", type_text.strip()):
                type_text = type_text.split(None, 1)[-1] if ' ' in type_text.strip() else type_text
            base = base_type_name(type_text)
            if base and (base in core_types or base in local_types or base in STDLIB_TYPES or base in ("Array", "Optional", "Set", "Dictionary")):
                out.append((m.start(), label, base, type_text.strip(), None))
    return out

def call_args(src, open_paren_idx):
    depth, i = 0, open_paren_idx
    for j in range(open_paren_idx, len(src)):
        if src[j] == "(": depth += 1
        elif src[j] == ")":
            depth -= 1
            if depth == 0:
                i = j
                break
    inside = src[open_paren_idx + 1:i]
    return split_args(inside), i

def arg_labels(clauses):
    labels, unlabeled = [], 0
    for clause in clauses:
        cm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*|_)\s*:", clause.strip())
        if cm and cm.group(1) != "_":
            labels.append(cm.group(1))
        else:
            unlabeled += 1
    return labels, unlabeled

def member_lookup(tname, mname):
    """All members named mname reachable without qualifier on type tname (Core or local)."""
    out = []
    for m in members.get(tname, []):
        if m["name"].split("(")[0] == mname: out.append((normalize_member(m), "core"))
    for m in local_members_map.get(tname, []):
        if m["name"] == mname: out.append((normalize_member(m), "local"))
    for m in local_ext.get(tname, []):
        if m["name"] == mname: out.append((normalize_member(m), "localext"))
    return out

def normalize_member(m):
    if "isStatic" not in m: m["isStatic"] = False
    if "type" not in m: m["type"] = None
    return m

def type_kind(tname):
    if tname in local_types: return local_types[tname]["kind"]
    if tname in core_types: return core_types[tname]["kind"]
    return None

# ---------------- scans ----------------

KEYWORDS = {
    "if","else","switch","case","default","guard","where","for","in","while","repeat","do","catch","try","as","is",
    "return","break","continue","fallthrough","throw","throws","rethrows","async","await","actor","func","let","var",
    "static","class","struct","enum","protocol","extension","import","typealias","associatedtype","some","any","weak",
    "unowned","private","fileprivate","internal","public","open","package","final","mutating","nonmutating","override",
    "init","self","Self","super","true","false","nil","guard","defer","with","never","inout","prefix","postfix","operator",
    "precedencegroup","required","convenience","indirect","optional","lazy","override","convenience","required",
}
# common SwiftUI/Foundation/UIKit type + constructor names, so we don't flag stdlib uses
STDLIB_TYPES = {
    # Swift language & stdlib
    "Bool","Int","Int8","Int16","Int32","Int64","UInt","UInt8","UInt16","UInt32","UInt64","Double","Float","Float16","Float64",
    "CGFloat","String","Substring","Character","Data","Void","Any","AnyObject","AnyView","AnyShape","Never","Optional","Result",
    "Array","Dictionary","Set","Sequence","Collection","RandomAccessCollection","BidirectionalCollection","Range","ClosedRange",
    "PartialRangeFrom","PartialRangeThrough","PartialRangeUpTo","IndexSet","IndexPath","Stride","Zip",
    "KeyPath","WritableKeyPath","PartialKeyPath","AnyKeyPath","ReferenceWritableKeyPath",
    "Date","TimeInterval","TimeZone","Locale","Calendar","DateComponents","DateInterval","NumberFormatter","ByteCountFormatter","Measurement",
    "URL","URLRequest","URLResponse","HTTPURLResponse","URLSession","URLComponents","URLQueryItem",
    "Error","Encodable","Decodable","Codable","CodingKey","JSONEncoder","JSONDecoder","PropertyListEncoder","ISO8601DateFormatter",
    "UnicodeScalar","CharacterSet","Scanner","NSDate","NSNumber","NSString","NSArray","NSDictionary","NSValue",
    "FileManager","ProcessInfo","OperationQueue","DispatchQueue","DispatchSource","DispatchGroup","DispatchSemaphore",
    "Task","TaskGroup","AsyncStream","AsyncThrowingStream","AsyncSequence","AsyncIteratorProtocol",
    "Duration","Clock","ContinuousClock","SuspendingClock","Instant","TaskPriority",
    "Binding","State","StateObject","ObservedObject","EnvironmentObject","FocusedValue","FocusedBinding","FocusedObject",
    "Published","ObservableObject","Observation","ObservationRegistrar",
    "MainActor","Sendable","Hashable","Equatable","Comparable","CaseIterable","RawRepresentable",
    "ExpressibleByStringLiteral","ExpressibleByIntegerLiteral","ExpressibleByFloatLiteral","ExpressibleByBooleanLiteral",
    "ExpressibleByNilLiteral","ExpressibleByArrayLiteral","ExpressibleByDictionaryLiteral",
    "CustomStringConvertible","CustomDebugStringConvertible","CustomLeafPropertyListConvertible","Encodable",
    "Bundle","UserDefaults","Notification","NotificationCenter","Timer","NotificationName",
    # C / Apple primitive and Security-framework tokens
    "CFNumber","CFString","CFDictionary","CFArray","CFBoolean","CFUUID","CFAllocator","CFError","CFAllocatorRef","CFDictionaryRef",
    "SecItemCopyMatching","SecItemAdd","SecItemDelete","SecItemUpdate","SecItemCopyAttributes","SecItemCopyMatchingResultType",
    "SecAccessControl","SecKeychainItem","SecKeychainItemDelete","SecCertificate","SecPolicy","SecTrust",
    # SwiftUI & UIKit & AppKit frameworks & their common types
    "View","App","Scene","WindowGroup","Settings","CommandGroup","CommandMenu","CommandKeyBinding",
    "Text","Button","Label","Image","Color","Font","Gradient","LinearGradient","RadialGradient","AngularGradient",
    "VStack","HStack","ZStack","Spacer","Divider","Group","ScrollView","LazyVStack","LazyHStack","List","Section",
    "Form","TabView","Picker","Toggle","TextField","SecureField","Stepper","Slider","DatePicker",
    "ColorPicker","Menu","ProgressView","Gauge","Link",
    "NavigationStack","NavigationLink","NavigationView","NavigationSplitView","GeometryReader","Canvas","Path","Shape",
    "Rectangle","RoundedRectangle","Circle","Ellipse","Capsule","ButtonStyle","ToggleStyle","ViewModifier","ViewBuilder",
    "Preference","PreferenceKey","TimelineView","TimelineSchedule","ImageRenderer","AttributedString","AttributeContainer",
    "ScrollViewReader","ScrollViewProxy","Namespace","AnyView","AnyTransition","AnyLayout","AnyShape","AnyShapeStyle",
    "Transition","Transaction","Animation","Spring","PhaseAnimator","KeyframeAnimator","Phase","TransactionAnimation",
    "Geometry","GeometryProxy","GeometryEffect","RelativePoint","CGVector","CGPoint","CGSize","CGRect","CGPath","CGAffineTransform",
    "UIColor","UIFont","UIImage","UIView","UIViewRepresentable","UIViewControllerRepresentable","UIHostingController",
    "UIWindow","UIApplication","UIScreen","UIScrollView","UITableView","UICollectionView","UIControl","UIButton","UILabel",
    "UITextView","UITextField","UIPasteboard","UIMenu","UIAction","UIMenuElement","UICommand","UIHostingConfiguration",
    "UIImagePickerController","UIActivityViewController","UIDocumentPickerViewController","UIViewController",
    "UIEdgeInsets","UITraitCollection","UIContentSizeCategory","UIUserInterfaceSizeClass","UIUserInterfaceIdiom",
    "AttributedString","AttributeContainer","AttributedStringKey","CustomAttributedStringKey","AttributeScope","SemanticMarkdownAttribute",
    "PHPhotoLibrary","PHImageManager","PHFetchResult","PHAsset","PHAssetCollection","PHContentEditingInput","PHContentEditingOutput",
    "PhotosPicker","PhotosPickerItem","AVAudioEngine","AVAudioSession","AVAudioPlayer","AVPlayer","AVPlayerLayer","AVPlayerItem",
    "SFSpeechRecognizer","SFSpeechAudioBufferRecognitionRequest","SFSpeechRecognitionRequest","SFSpeechRecognitionTask","SFTranscription",
    "SwiftTerm","TerminalView","Timer","Timer","UUID","NSUUID","RegularExpression","NSRegularExpression",
    "CoreGraphics","CoreImage","CIFilter","CIContext","CIImage","Metal","MTKView","CALayer","CATransaction","CADisplayLink",
    "Combine","AnyPublisher","PassthroughSubject","CurrentValueSubject","Just","Future","Deferred","Published",
    "Highlighter","Document","Markdown","TerminalView","SwiftTerm","TerminalViewDelegate","ASTNode","NSMutableAttributedString","NSAttributedString","NSLayoutManager","NSTextContainer","UITextView","UIKeyCommand","UIKeyboard","UIResponder","UIControl","UIStackView","UIImageView","UIEdgeInsets",
    "UniformTypeIdentifiers","UTType","NSItemProvider","NSItemProviderWriting","NSItemProviderReading",
    "Swift","Foundation","UIKit","Security","CoreGraphics","CoreServices","UniformTypeIdentifiers","Darwin","Glibc",
    "CFStringRef","CFNumberRef","CFDictionaryRef","CFArrayRef","CFDataRef","CFURLRef",
    "Environment","FocusState","AppStorage","SceneStorage","EmptyView","ForEach","Section","Group","AnyTransition",
    "Context","Coordinator","Configuration","EnvironmentKey",
    "ColorScheme","ColorSchemeLayoutDirection","Identifiable","Codable","Equatable","Hashable","NSObject",
    "UIImagePickerControllerDelegate","UINavigationControllerDelegate","UIPickerViewDelegate","UIPickerViewDataSource",
    "UITextViewDelegate","UITextFieldDelegate","UIScrollViewDelegate","UITableViewDelegate","UITableViewDataSource",
    "UICollectionViewDelegate","UICollectionViewDataSource","UIApplicationDelegate","UIWindowSceneDelegate",
    "ObservableObject","ObservableObjectPublisher","Published","State","Binding","FocusState",
}

def is_known_type(t):
    return t in core_types or t in local_types or t in STDLIB_TYPES or t in KEYWORDS or t.startswith("_")

findings = []

def add(f, line, col, category, message):
    findings.append((f, line, col, category, message))

def pos_of(src, idx):
    line = src.count("\n", 0, idx) + 1
    col = idx - src.rfind("\n", 0, idx)
    return line, col

# ---- typed-variable discovery per file (two passes: declared types, then multi-hop inference) ----
pat_typed = re.compile(r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^\n={]+?)(?:\s*=|\s*\{|$)", re.M)
pat_ctor  = re.compile(r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\(")
pat_chain = re.compile(r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)(?=\s*[({)\\],;]|\s*\n|\s*$)")
UNKNOWN = "?"

def infer_elem(r):
    if not r:
        return None
    m = re.match(r"^\[([A-Za-z_][A-Za-z0-9_]*)", r)
    if m:
        return m.group(1)
    m2 = re.match(r"^(?:Set<|Dictionary<)([A-Za-z_][A-Za-z0-9_]*)", r)
    return m2.group(1) if m2 else None

def build_name_index(dl):
    idx = {}
    for pos, n, t, r, e in dl:
        idx.setdefault(n, []).append((pos, t, e if e else infer_elem(r)))
    return idx

def decl_at_idx(idx, name, pos):
    lst = idx.get(name)
    if not lst:
        return None
    best = None
    for p, t, e in lst:  # lst is position-sorted (dl is sorted)
        if p <= pos:
            best = (t, e)
        else:
            break
    return best

# positioned typed declarations per file (params shadow lets within their scope)
decls = {}
for f in files:
    src = strip_source(open(f).read())
    dl = []
    for m in pat_typed.finditer(src):
        base = base_type_name(m.group(2))
        if base:
            dl.append((m.start(), m.group(1), base, m.group(2).strip(), None))
    for m in pat_ctor.finditer(src):
        t = m.group(2).split(".")[-1]
        if is_known_type(t) and t != "Self":
            dl.append((m.start(), m.group(1), t, None, None))
    dl.extend(param_decls(f, src))

    # for-loop bindings inherit the element type of the (possibly chained) collection
    pat_for = re.compile(r"\bfor\s+(?:[A-Za-z_][A-Za-z0-9_]*\s+)?(?:let\s+|var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s+in\s+([^\n{]+)")

    def coll_elem_of(expr, pos):
        """Resolve `a.b.c` (the for-in collection expression) to (base, elem)."""
        fm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)", expr.strip())
        if not fm:
            return None
        parts = fm.group(1).split(".")
        best = None
        for p, n, t, r, e in dl:
            if p <= pos and n == parts[0]:
                best = (t, e if e else infer_elem(r))
        if best is None:
            return None
        cur, cur_elem = best
        for part in parts[1:]:
            if cur in ("Array", "Optional", "Set", "Dictionary"):
                return (cur, cur_elem)
            hits = [mm.get("type") or "" for mm in members.get(cur, []) if mm["name"].split("(")[0] == part]
            for mm in local_members_map.get(cur, []):
                if mm["name"].split("(")[0] == part:
                    hits.append(mm.get("type") or "")
            for mm in local_ext.get(cur, []):
                if mm["name"].split("(")[0] == part:
                    hits.append(mm.get("type") or "")
            if not hits:
                return None
            t2 = hits[0].strip()
            arr = re.match(r"^\[([A-Za-z_][A-Za-z0-9_]*)", t2)
            if arr:
                el = arr.group(1)
                if el in core_types or el in local_types:
                    cur, cur_elem = "Array", el
                    continue
                return None
            b2 = base_type_name(t2)
            if not b2:
                return None
            cur, cur_elem = b2, None
        return (cur, cur_elem)

    for m in pat_for.finditer(src):
        resolved = coll_elem_of(m.group(2), m.start())
        if resolved:
            cur, elem = resolved
            if cur in ("Array", "Set", "Dictionary") and elem and (elem in core_types or elem in local_types):
                dl.append((m.start(), m.group(1), elem, None, elem))
    # enum case bindings (`case .x(let a, let b)` / `case let .x(a, b)`) are untyped here:
    # mark them UNKNOWN so they shadow any stale lets of the same name
    for m in re.finditer(r"case\s+(?:let\s+)?\.?([A-Za-z_][A-Za-z0-9_.]*)\s*\(([^)]*)\)", src):
        for clause in split_args(m.group(2)):
            cm = re.match(r"^(?:let|var|_|inout)?\s*([A-Za-z_][A-Za-z0-9_]*)(?:\s*:.*)?$", clause.strip())
            if cm and cm.group(1) not in ("let", "var", "_"):
                dl.append((m.start(), cm.group(1), UNKNOWN, None, None))
    # infer `let x = <chain>` and `let x = f(...)` bindings positionally,
    # so they shadow earlier params/lets of the same name inside their scope
    dl.sort(key=lambda x: x[0])
    idx = build_name_index(dl)
    func_returns = index.get("local_func_returns", {})

    def resolve_idx(chain, pos):
        parts = chain.split(".")
        best = decl_at_idx(idx, parts[0], pos)
        if best is None:
            return None
        cur, _ = best
        if cur == UNKNOWN:
            return None
        if cur in ("Array", "Optional", "Set", "Dictionary"):
            return cur
        for part in parts[1:]:
            if cur in ("Array", "Optional", "Set", "Dictionary"):
                return cur
            hits = [mm.get("type") or "" for mm in members.get(cur, []) if mm["name"].split("(")[0] == part]
            for mm in local_members_map.get(cur, []):
                if mm["name"].split("(")[0] == part:
                    hits.append(mm.get("type") or "")
            for mm in local_ext.get(cur, []):
                if mm["name"].split("(")[0] == part:
                    hits.append(mm.get("type") or "")
            if not hits:
                return None
            t2 = hits[0].strip()
            arr = re.match(r"^\[([A-Za-z_][A-Za-z0-9_]*)", t2)
            if arr and (arr.group(1) in core_types or arr.group(1) in local_types):
                cur = "Array"
                continue
            b2 = base_type_name(t2)
            if not b2:
                return None
            cur = b2
        return cur

    for m in pat_chain.finditer(src):
        name, chain = m.group(1), m.group(2)
        b = resolve_idx(chain, m.start())
        if b:
            dl.append((m.start(), name, b, None, None))
            idx.setdefault(name, []).append((m.start(), b, None))
    for m in re.finditer(r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(", src):
        name, func = m.group(1), m.group(2)
        raws = func_returns.get(func)
        if raws and len(set(raws)) == 1 and raws[0]:
            raw = raws[0]
            base = base_type_name(raw)
            if base:
                elem = infer_elem(raw)
                dl.append((m.start(), name, base, raw, elem))
                idx.setdefault(name, []).append((m.start(), base, elem))

    # closure parameters whose element type comes from a collection expression:
    #   ForEach(xs) { x in ... }, xs.map { x in ... }, xs.first(where: { x in ... })
    def bind_element(name, expr, pos):
        resolved = coll_elem_of(expr, pos)
        if not resolved:
            return
        cur, elem = resolved
        if cur in ("Array", "Set", "Dictionary") and elem and (elem in core_types or elem in local_types):
            dl.append((pos, name, elem, None, elem))
            idx.setdefault(name, []).append((pos, elem, elem))

    for m in re.finditer(r"\bForEach\(\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*[^)\n]*\)\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)\s+in", src):
        bind_element(m.group(2), m.group(1), m.start())
    for m in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\.(?:map|filter|compactMap|flatMap|forEach|allSatisfy|sorted|first|contains|firstIndex|lastIndex)\s*(?:\([^)\n]*)?\{\s*([A-Za-z_][A-Za-z0-9_]*)\s+in", src):
        bind_element(m.group(2), m.group(1), m.start())

    # refine Array-of-T element types from raw spellings in the same file
    for i, (pos, n, t, r, e) in enumerate(dl):
        if e is None and r and t in ("Array", "Set", "Dictionary"):
            m = re.match(r"^\[([A-Za-z_][A-Za-z0-9_]*)", r)
            if m:
                elem = m.group(1)
                if elem in core_types or elem in local_types:
                    dl[i] = (pos, n, t, r, elem)

    dl.sort(key=lambda x: x[0])
    decls[f] = build_name_index(dl)

def decl_at(f, name, pos):
    return decl_at_idx(decls[f], name, pos)

# ---- main scan: member chains, inits, statics, bare calls, duplicates ----
for f in files:
    raw = open(f).read()
    src = strip_source(raw)

    # ---- member access chains on typed variables ----
    for m in re.finditer(r"(?<![A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_]*)((?:\??\.[A-Za-z_][A-Za-z0-9_]*)+)", src):
        head, tail = m.group(1), m.group(2)
        parts = [p.strip("?") for p in tail.split(".") if p and p != "?"]
        line, col = pos_of(src, m.start())
        if head == "Self" or head == "self":
            continue
        if head in STDLIB_TYPES or head in KEYWORDS or head.startswith("$"):
            # stdlib type or keyword used as a value head — not auditable against our API
            continue
        decl = decl_at(f, head, m.start())
        if decl is not None:
            head_type, elem = decl
            if head_type == UNKNOWN:
                continue
            if head_type in STDLIB_TYPES or head_type in ("Array", "Optional", "Set", "Dictionary"):
                continue
            if head_type in local_opaque:
                continue
            candidates = [head_type]
            ok = True
            for i, part in enumerate(parts):
                nxt = []
                for t in candidates:
                    if t in STDLIB_TYPES or t in ("Array", "Optional", "Set", "Dictionary"):
                        # opaque Foundation/UIKit member — always accepted
                        nxt.append(t)
                        continue
                    hits = member_lookup(t, part)
                    if not hits:
                        add(f, line, col, "missing-member",
                            f"{t} has no (public) member '{part}'")
                        ok = False
                        break
                    for mm, _ in hits:
                        base = base_type_name(mm.get("type")) if mm.get("type") else None
                        if base:
                            nxt.append(base)
                if not ok:
                    break
                candidates = list(dict.fromkeys(nxt))
                if candidates == ["Array"] or candidates == ["Optional"] or candidates == ["Set"] or candidates == ["Dictionary"]:
                    candidates = []
                    break
                if not candidates:
                    break
        elif head in core_types or head in local_types:
            # static / enum-case access:  Type.member
            t = head
            for i, part in enumerate(parts):
                if part == "self":
                    break  # metatype access — always legal
                kind = type_kind(t)
                if kind == "swift.enum":
                    cases = enum_cases.get(t, [])
                    if part in cases:
                        # any further components? must be a member of the case's payload — stop
                        break
                    statics = [mm for mm in members.get(t, []) if mm["name"].split("(")[0] == part and mm["isStatic"]]
                    nested = [nt for nt in core_types if nt == part]
                    if statics or part in core_types or part in local_types:
                        if part in core_types: t = part; continue
                        break
                    add(f, line, col, "missing-case",
                        f"enum {t} has no case or static member '{part}'")
                    break
                else:
                    hits = member_lookup(t, part)
                    stat = [h for h in hits if h[0]["isStatic"]]
                    if stat or part in core_types or part in local_types:
                        if part in core_types: t = part; continue
                        if part in local_types: t = part; continue
                        break
                    add(f, line, col, "missing-static",
                        f"{t} has no static member '{part}'")
                    break
        # else: unresolved head — checked by the bare-function/unknown-type scans below

    # ---- bare enum cases: `let x: SomeEnum = .someCase` ----
    for m in re.finditer(r"\b(?:let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)\??\s*=\s*\.([A-Za-z_][A-Za-z0-9_]*)", src):
        tname, case = m.group(1).split(".")[-1], m.group(2)
        if case in ("init", "self"):
            continue
        if tname not in core_types and tname not in local_types:
            continue
        kind = type_kind(tname)
        if kind not in ("swift.enum", "enum"):
            continue
        cases = set(enum_cases.get(tname, []))
        cases |= {mm["name"].split("(")[0] for mm in members.get(tname, []) if mm.get("kind") == "swift.enum.case"}
        cases |= {mm["name"].split("(")[0] for mm in local_members_map.get(tname, []) if mm.get("kind") == "case"}
        if case not in cases:
            line, col = pos_of(src, m.start())
            add(f, line, col, "missing-case", f"enum {tname} has no case '{case}'")

    # ---- call sites: NAME(...) ----
    for m in re.finditer(r"(?<![A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_]*)\s*\(", src):
        name = m.group(1)
        line, col = pos_of(src, m.start())
        # keywords/stdlib/ctor-of-known-type/func-of-typed-var handled elsewhere
        if name in KEYWORDS:
            continue
        # is this a constructor for a known type?
        if name in core_types or name in local_types:
            t = name
            clauses, _ = call_args(src, m.end() - 1)
            labels, unlabeled = arg_labels(clauses)
            in_sigs = [mm for mm in members.get(t, []) if mm["kind"] == "swift.init"]
            # match by arity (clause count) first, then label containment
            candidates = [s for s in in_sigs if len(s["labels"]) == len(labels) + unlabeled]
            if not candidates:
                candidates = in_sigs
            def labels_of(s): return [l for l in s["labels"] if l != "_"]
            ok = False
            for s in candidates:
                sl = set(labels_of(s))
                if all(l in sl or l == "_" for l in labels):
                    ok = True
                    break
            if not ok and candidates:
                known = sorted({l for s in in_sigs for l in labels_of(s)})
                add(f, line, col, "init-labels",
                    f"argument labels ({', '.join(labels)}) match no {t} init (known labels: {', '.join(known) or 'none'})")
            # possibly missing required labels (only when some init matched well enough to compare)
            for s in candidates:
                sl = set(labels_of(s))
                if all(l in sl or l == "_" for l in labels):
                    required_missing = [l for l in sl - set(labels) if not s.get("defaults", {}).get(l, False)]
                    if required_missing:
                        add(f, line, col, "init-missing-label",
                            f"{t} init call may be missing required argument label(s): {', '.join(required_missing)}")
                    break
            continue
        if name in local_free:
            continue
        # common stdlib-style lowercase calls and SwiftUI view builders
        if name[0].islower():
            if name in {"print","assert","fatalError","precondition","assertionFailure","min","max","abs","stride",
                        "swap","zip","map","filter","sorted","reduce","split","joined","prefix","suffix","drop",
                        "contains","index","append","insert","remove","insert","uppercased","lowercased","trim",
                        "range","compactMapValues","forEach","enumerated","joined","split","compactMap","flatMap",
                        "prefix","last","first","contains","allSatisfy","containswhere","withUnsafeBytes","withUnsafeMutableBytes",
                        "withUnsafeTemporaryRoots","withExtendedLifetime","withTaskGroup","withTaskCancellationHandler",
                        "withCheckedContinuation","withUnsafeThrowingContinuation","withThrowingDiscardingTaskGroup","withThrowingTaskGroup",
                        "withTaskGroup","withGracefulTaskGroup","withThrowingTaskGroup","withUnsafeContinuation",
                        "registerSubview","addSubview","insertSubview","setNeedsLayout","layoutIfNeeded","configure",
                        "makeUIView","updateUIView","makeUIViewController","updateUIViewController","makeNSView","updateNSView",
                        "dismantleUIView","dismantleUIViewController","makeCoordinator","updateCoordinator","dismantleCoordinator",
                        "updateLayout","didReceive","setValue","getValue","advance","retreat","advanceToEnd","retreatToStart",
                        "advanceToNextSegment","retreatToNextSegment","advancing","retreating","focusNext","focusPrevious"}:
                continue
            continue  # lowercase bare calls: nearly always stdlib/local; skipped by design
        # PascalCase: unknown type?
        if name[0].isupper():
            if name in STDLIB_TYPES or name in KEYWORDS: continue
            add(f, line, col, "unknown-type",
                f"unknown type '{name}' referenced as a constructor")

    # ---- unresolved PaseoUI-internal symbols used as values/types in calls handled above; ----
    # ---- here: unknown PascalCase tokens that aren't declared anywhere ----
    for m in re.finditer(r"(?<![A-Za-z0-9_.@])([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_])", src):
        name = m.group(1)
        if name[0].isupper() and name not in core_types and name not in local_types and name not in STDLIB_TYPES and name not in KEYWORDS:
            line, col = pos_of(src, m.start())
            add(f, line, col, "unknown-type",
                f"unknown type '{name}' referenced")

print("scanning", len(files), "files...")
by_cat = collections.Counter(c for _, _, _, c, _ in findings)
print("findings by category:", dict(by_cat))
for f, line, col, cat, msg in sorted(findings, key=lambda x: (x[0], x[1], x[2])):
    print(f"{f}:{line}:{col}: [{cat}] {msg}")

dups = index.get("duplicate_types", {})
if dups:
    print(f"duplicate-type: {len(dups)} top-level type name(s) declared more than once:")
    for name, fs in sorted(dups.items()):
        print(f"  {name}: {', '.join(sorted(set(fs)))}")
else:
    print("duplicate-type: none")

actionable = [x for x in findings if x[3] != "unknown-type"]
sys.exit(1 if actionable else 0)
