#!/usr/bin/env python3
"""Engine of Performance/scripts/final-check.sh. Standard library only.

GUARANTEES: the AUTO checks below are exact patterns (a hit is a violation of a MUST item), run on the
lines you changed. NEVER CLAIMS: anything about timing or semantics. Heuristic hits are not violations;
they are listed as MANUAL questions with file:line. See Performance/FINAL-CHECK.md.
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PERF = os.path.dirname(HERE)
REPO = os.path.dirname(PERF)

# --------------------------------------------------------------------------------------------------
# Source model: comment/string stripping and a brace-frame tree
# --------------------------------------------------------------------------------------------------


def scan(lines):
    """Returns (code, skel). code: comments removed, string text kept. skel: strings removed too."""
    code, skel = [], []
    in_block = 0
    in_ml = False
    for ln in lines:
        c, s = [], []
        i, n = 0, len(ln)
        while i < n:
            ch, two = ln[i], ln[i:i + 2]
            if in_block:
                if two == "*/":
                    in_block -= 1
                    i += 2
                else:
                    i += 1
                continue
            if in_ml:
                if ln[i:i + 3] == '"""':
                    in_ml = False
                    i += 3
                else:
                    i += 1
                continue
            if two == "//":
                break
            if two == "/*":
                in_block += 1
                i += 2
                continue
            if ln[i:i + 3] == '"""':
                in_ml = True
                i += 3
                c.append('""')
                s.append('""')
                continue
            if ch == '"':
                c.append(ch)
                i += 1
                while i < n and ln[i] != '"':
                    if ln[i] == "\\" and ln[i + 1:i + 2] == "(":
                        depth, j = 0, i + 1
                        while j < n:
                            if ln[j] == "(":
                                depth += 1
                            elif ln[j] == ")":
                                depth -= 1
                                if depth == 0:
                                    break
                            j += 1
                        c.append(ln[i:j + 1])
                        i = j + 1
                        continue
                    if ln[i] == "\\":
                        c.append(ln[i:i + 2])
                        i += 2
                        continue
                    c.append(ln[i])
                    i += 1
                c.append('"')
                s.append('""')
                i += 1
                continue
            c.append(ch)
            s.append(ch)
            i += 1
        code.append("".join(c))
        skel.append("".join(s))
    return code, skel


class Frame:
    __slots__ = ("open", "end", "header", "kind", "name", "conforms", "mainactor", "col")

    def __init__(self, open_idx, header, kind, name, conforms, mainactor, col):
        self.open, self.end, self.header = open_idx, open_idx, header
        self.kind, self.name, self.conforms, self.mainactor, self.col = kind, name, conforms, mainactor, col


RX_BODY = re.compile(r"\bvar\s+body\s*:\s*some\s+View")
RX_VIEWSCOPE = re.compile(r"\b(var|func)\s+\w+[^={]*(:|->)\s*some\s+View\b")
RX_INIT = re.compile(r"\binit[?!]?\s*\(")
RX_FUNC = re.compile(r"\bfunc\s+(\w+)")
RX_TYPE = re.compile(r"\b(struct|class|actor|enum|extension|protocol)\s+(\w+)")
RX_COMPUTED = re.compile(r"\bvar\s+(\w+)\s*:\s*[^={]+$")


def classify(header, prev_lines):
    attrs = " ".join(prev_lines)
    if RX_BODY.search(header):
        return "body", "body", "", False
    if RX_VIEWSCOPE.search(header) or ("@ViewBuilder" in attrs and re.search(r"\b(var|func)\s+\w+", header)):
        m = re.search(r"\b(?:var|func)\s+(\w+)", header)
        return "viewscope", m.group(1) if m else "", "", False
    if RX_INIT.search(header):
        return "init", "init", "", False
    m = RX_FUNC.search(header)
    if m:
        return "func", m.group(1), "", False
    m = RX_TYPE.search(header)
    if m:
        rest = header[m.end():]
        cm = re.search(r":\s*(.*?)(?:\bwhere\b|$)", rest)
        conforms = cm.group(1) if cm else ""
        main = "@MainActor" in header or "@MainActor" in attrs
        if "@Observable" in header or "@Observable" in attrs:
            main = main or False
        return "type", m.group(2), conforms + " " + attrs, main
    m = RX_COMPUTED.search(header)
    if m:
        return "computed", m.group(1), "", False
    return "other", "", "", False


class SwiftFile:
    def __init__(self, rel, text, changed=None, all_lines=False):
        self.rel = rel
        self.raw = text.split("\n")
        self.code, self.skel = scan(self.raw)
        n = len(self.raw)
        self.changed = set(range(n)) if all_lines or changed is None else {c - 1 for c in changed if 0 <= c - 1 < n}
        self.enc = [[] for _ in range(n)]
        self.frames = []
        stack = []
        for i, line in enumerate(self.skel):
            seen = list(stack)
            for col, ch in enumerate(line):
                if ch == "{":
                    head = line[:col]
                    k, j = 0, i
                    while head.count(")") > head.count("(") and j > 0 and k < 8:
                        j -= 1
                        k += 1
                        head = self.skel[j] + " " + head
                    prev = [self.skel[x].strip() for x in range(max(0, j - 2), j) if self.skel[x].strip().startswith("@")]
                    # attribute lines directly above (e.g. @MainActor, @ViewBuilder)
                    prev += [self.skel[j].strip()] if self.skel[j].strip().startswith("@") and j != i else []
                    kind, name, conforms, main = classify(head, prev)
                    fr = Frame(i, head, kind, name, conforms, main, col)
                    stack.append(fr)
                    self.frames.append(fr)
                    seen.append(fr)
                elif ch == "}" and stack:
                    fr = stack.pop()
                    fr.end = i
            self.enc[i] = seen
        for fr in stack:
            fr.end = n - 1

    # helpers ---------------------------------------------------------------------------------
    def changed_lines(self):
        for i in sorted(self.changed):
            if self.code[i].strip():
                yield i, self.code[i]

    def frames_at(self, i, own_rx=None):
        """Frames enclosing the content of line i. With own_rx, drops the frame the match itself opens."""
        fr = self.enc[i]
        if own_rx is not None:
            for k, f in enumerate(fr):
                if f.open == i and own_rx.search(f.header):
                    return fr[:k]
        return list(fr)

    def in_scope(self, i, kinds, own_rx=None):
        return any(f.kind in kinds for f in self.frames_at(i, own_rx))

    def enclosing_type(self, i):
        for f in reversed(self.enc[i]):
            if f.kind == "type":
                return f
        return None

    def waiver(self, i, cid):
        for j in (i, i - 1):
            if j < 0:
                continue
            m = re.search(r"perf-ok:\s*((?:[A-Z]\d+\s*,?\s*)+)\s+(\S.{6,})", self.raw[j])
            if m and cid in re.findall(r"[A-Z]\d+", m.group(1)):
                return m.group(2).strip()
        return None


def receiver_root(code, dot_index):
    """(expression, root identifier) of the receiver that ends just before `dot_index`."""
    j = dot_index
    while j > 0 and code[j - 1] in " \t":
        j -= 1
    start, depth = j, 0
    while start > 0:
        ch = code[start - 1]
        if ch in ")]}":
            depth += 1
        elif ch in "([{":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and not (ch.isalnum() or ch in "_."):
            break
        start -= 1
    expr = code[start:j].strip()
    m = re.match(r"[A-Za-z_]\w*", expr)
    return expr, (m.group(0) if m else "")


def symbol_at(f, i):
    """The innermost function or computed property name around line i ('' when none)."""
    for fr in reversed(f.enc[i]):
        if fr.kind in ("func", "computed"):
            return fr.name
    t = f.enclosing_type(i)
    return t.name if t else ""


EVENT_RX = re.compile(
    r"\bTask\b|\.task\b|\bButton\b|\.onTapGesture|\.onLongPressGesture|\.refreshable|\.onChange|\.onReceive|"
    r"\.onSubmit|\baction\s*:|\.swipeActions|DispatchQueue|\.contextMenu|\.confirmationDialog|\.onDisappear")
STORE_NAMES = re.compile(r"\b(store|draft|controller|session|conversation|model|directory)\b")
BIG = r"(agents|workspaces|turns|rows|messages|entries|timeline|conversations|files|items|segments|pieces|lines|projects|schedules|terminals)"
BIG_WORDS = set(BIG.strip("()").split("|"))
# A collection whose size grows with the conversation, a list or a directory. A scan over one of these is
# only a question (H05, H29); a scan over a single item (one turn's rows, one message's pieces) never is.
COLLECTION_ROOTS = BIG_WORDS | {"all", "store", "session", "draft", "model", "controller", "directory",
                                "conversation", "timeline", "built", "visibleTurnIds", "windowedTurns"}
ITEM_ROOTS = {"turn", "piece", "row", "segment", "item", "message", "entry", "line", "group", "section",
              "work", "card", "cell", "agent", "project", "schedule", "terminal", "file", "panel", "tab", "part"}
MODEL_ROOTS = {"controller", "store", "session", "draft", "model", "directory", "conversation", "transcript"}
GEO_RX = re.compile(r"onGeometryChange|onScrollGeometryChange|GeometryReader|onPreferenceChange|onScrollPhaseChange")

# --------------------------------------------------------------------------------------------------
# Path tags and features
# --------------------------------------------------------------------------------------------------


def path_tags(rel):
    tags = set()
    if rel.startswith("Packages/PaseoUI/Sources/"):
        tags.add("ui")
    if rel.startswith("Packages/PaseoCore/Sources/"):
        tags.add("core")
    if rel.startswith("App/"):
        tags.add("app")
    if "/Tests/" in rel or rel.startswith("Tests/"):
        tags.add("test")
    base = os.path.basename(rel)
    if re.search(r"Transcript|/Turn/|Prose|ChatTurns|Reveal|ChatWorkGroup", rel):
        tags.add("stream")
    if re.search(r"Row|Cell", base) or "/Sidebar/" in rel:
        tags.add("row")
    if re.search(r"Composer|Keyboard|Mention|/Draft/", rel):
        tags.add("composer")
    if re.search(r"/Shell/|Drawer|Sidebar|WorkspacePanel", rel):
        tags.add("shell")
    if re.search(r"Media|/Rich/|Card|Image|Video|Audio|Web", rel):
        tags.add("media")
    if "/PaseoStore/" in rel or re.search(r"Store\.swift$|HostSession|TimelineState", rel):
        tags.add("store")
    if rel.startswith("App/") or re.search(r"Warmup|Font|Launch|AppModel", rel):
        tags.add("launch")
    if re.search(r"/(Settings|Workspace|Terminals|History|Schedules)/", rel):
        tags.add("lists")
    return tags


HOT_TAGS = {"stream", "composer", "shell", "media", "store", "launch"}

PATH_ITEMS = {
    "stream": ["M09", "M18", "M20", "M21"],
    "row": ["M11", "M14", "M16"],
    "composer": ["M18", "M27", "M34"],
    "shell": ["M07", "M18", "M35"],
    "media": ["M18", "M29", "M31"],
    "store": ["M04", "M05", "M26", "M30"],
    "launch": ["M31", "M33"],
    "lists": ["M12", "M16", "M18"],
    # any file in the two compiled packages: a change can always move per-frame work into a body,
    # which is the question nothing else asks for every .swift file.
    "ui": ["M18"],
    "core": ["M18"],
}

# id, name, regex on changed code, MUST items to ask, PATTERNS files
FEATURES = [
    ("F01", "observable model (@Observable / withObservationTracking)", r"@Observable|@ObservationIgnored|withObservationTracking", ["M04", "M05"], ["observation-and-invalidation", "stores-and-core"]),
    ("F02", "lists and stacks (ForEach / List / Lazy* / ScrollView)", r"\bForEach\b|\bList\s*[\({]|LazyVStack|LazyHStack|LazyVGrid|\bScrollView\b", ["M09", "M11", "M12", "M14", "M16"], ["rows-and-lists", "lazy-stacks-and-scrolling"]),
    ("F03", "text input / keyboard", r"\bTextField\b|\bTextEditor\b|UITextView|UITextField|becomeFirstResponder|FocusState|keyboardWill", ["M18", "M27", "M34"], ["uikit-interop-and-keyboard"]),
    ("F04", "images, audio, video", r"AsyncImage|UIImage|CGImageSource|AVPlayer|AVAudio|PHPicker|Image\(uiImage", ["M18", "M29", "M31"], ["media-and-images"]),
    ("F05", "async work (Task / await / queues / streams)", r"\bTask\b|\basync\b|\bawait\b|DispatchQueue|AsyncStream|\bactor\b", ["M25"], ["concurrency-and-main-thread"]),
    ("F06", "timers, display links, endless animation", r"\bTimer\.|CADisplayLink|TimelineView|Task\.sleep|\.repeatForever", ["M25", "M37"], ["concurrency-and-main-thread", "animation-and-drawer"]),
    ("F07", "caches and memoisation", r"NSCache|\b[cC]ache\b|[mM]emo\b|[mM]emoized|static var\s+\w+\s*:\s*\[", ["M29", "M30"], ["caches-and-memory"]),
    ("F08", "UIKit representable", r"UIViewRepresentable|UIViewControllerRepresentable|updateUIView", ["M34", "M35"], ["uikit-interop-and-keyboard"]),
    ("F09", "animation", r"withAnimation|\.animation\(|\.transition\(|matchedGeometryEffect|\bMotion\.", ["M37", "M35"], ["animation-and-drawer"]),
    ("F10", "store / @MainActor model writes", r"@MainActor\s+(final\s+)?class|@Observable\s*\n?\s*(public\s+)?(final\s+)?class|private\(set\) var", ["M04", "M26", "M30"], ["stores-and-core"]),
    ("F11", "JSON / Codable", r"JSONDecoder|JSONEncoder|\bCodable\b|\bDecodable\b|PropertyListDecoder", ["M26", "M18"], ["concurrency-and-main-thread"]),
    ("F12", "files, Keychain, UserDefaults, pasteboard", r"FileManager|Data\(contentsOf|String\(contentsOf|SecItem|Keychain|UserDefaults|\.write\(to|UIPasteboard", ["M26", "M27", "M33"], ["concurrency-and-main-thread", "launch-and-startup"]),
    ("F13", "web views and link previews", r"WKWebView|WebKit|LPLinkView|LPMetadataProvider", ["M31", "M18"], ["media-and-images"]),
    ("F14", "gestures and scrolling", r"DragGesture|UIPanGestureRecognizer|UIGestureRecognizer|\.gesture\(|simultaneousGesture|highPriorityGesture|UIScrollView|scrollPosition|onScrollGeometryChange|scrollTo\(", ["M35", "M21", "M14"], ["animation-and-drawer", "lazy-stacks-and-scrolling"]),
    ("F15", "text, markdown, code rendering", r"AttributedString|NSAttributedString|Markdown|TextRenderer|textSelection|Highlighter", ["M18", "M20", "M29"], ["text-markdown-code"]),
    ("F16", "launch path", r"@main|WindowGroup|didFinishLaunching|scenePhase|Warmup|CTFontManager", ["M33", "M31"], ["launch-and-startup"]),
    ("F17", "view identity", r"\.id\(|ForEach\([^)]*id:", ["M09"], ["identity-and-streaming"]),
    ("F19", "view state reads (@State / @Environment / @Bindable)", r"@Environment\(|@State\b|@Bindable", ["M01", "M07"], ["observation-and-invalidation"]),
    ("F18", "sheets, menus, popovers", r"\.sheet\(|\.popover\(|\.fullScreenCover|\.contextMenu|\.confirmationDialog|\.alert\(|\bMenu\s*[\({]", ["M12", "M11"], ["rows-and-lists"]),
]
FEATURE_RX = {f[0]: re.compile(f[2]) for f in FEATURES}

# --------------------------------------------------------------------------------------------------
# AUTO checks: exact patterns. A hit is a violation.
# --------------------------------------------------------------------------------------------------


def arg_of(code, start):
    depth = 0
    for j in range(start, len(code)):
        if code[j] == "(":
            depth += 1
        elif code[j] == ")":
            depth -= 1
            if depth == 0:
                return code[start + 1:j]
    return code[start + 1:]


def c01(f):  # .id() with a value that changes while content streams
    for i, c in f.changed_lines():
        if "Color.clear" in c or "rowAnchor" in c:
            continue
        for m in re.finditer(r"\.id\(", c):
            a = arg_of(c, m.end() - 1)
            if re.search(r"seqEnd|UUID\(\)|Date\(\)|Date\.now|hashValue|\.count\b|\.text\b|\.length\b|\.endIndex|random", a):
                yield i, ".id() takes a value that changes while content streams or types: " + a.strip()[:60]


def c03(f):  # Binding(get:) reading a store inside an init
    for i, c in f.changed_lines():
        m = re.search(r"Binding\(\s*get:(.*)", c)
        if m and STORE_NAMES.search(m.group(1)) and f.in_scope(i, {"init"}):
            yield i, "Binding(get:) reads a store inside an init: the parent becomes a dependency of the value"


def c04(f):  # object created in a @State default
    sfx = r"(Controller|Engine|Store|Session|Monitor|Service|Coordinator|Recorder|Player|Manager|Client|Connection)"
    rx1 = re.compile(r"@State\b[^=\n]*=\s*[A-Z]\w*" + sfx + r"\(")
    rx2 = re.compile(r"\bState\(initialValue:\s*[A-Z]\w*" + sfx + r"\(")
    for i, c in f.changed_lines():
        t = f.enclosing_type(i)
        if t and re.search(r"\bApp\b", t.conforms):
            continue  # the App struct is created once
        if rx1.search(c) or rx2.search(c):
            yield i, "object created in a @State default / State(initialValue:): it is built again on every parent pass"


def c06(f):  # closure stored in a Row/Cell view
    rx = re.compile(r"^\s*(?:@\w+(?:\(.*?\))?\s+)*(?:\w+\s+)*(?:let|var)\s+\w+\s*:\s*\(*\s*(?:@escaping\s*)?\([^()]*\)\s*(?:async\s*)?(?:throws\s*)?->")
    for i, c in f.changed_lines():
        t = f.enclosing_type(i)
        if not t or not re.search(r"(Row|Cell)$", t.name) or "View" not in t.conforms:
            continue
        if f.enc[i] and f.enc[i][-1] is not t:
            continue  # only direct members of the type
        if rx.search(c) and not c.rstrip().endswith("{"):
            yield i, "closure stored in %s: a closure is never equal, the row cannot skip body (take a value + an actions object)" % t.name


def c08(f):  # formatter/regex/coder constructed in a view scope
    rx = re.compile(r"\b(DateFormatter|NumberFormatter|ISO8601DateFormatter|ByteCountFormatter|RelativeDateTimeFormatter|MeasurementFormatter|DateComponentsFormatter|DateIntervalFormatter|JSONDecoder|JSONEncoder|NSRegularExpression|NLTagger|NLLanguageRecognizer|NSDataDetector)\s*\(|\btry\??\s+Regex\s*\(")
    for i, c in f.changed_lines():
        if not f.in_scope(i, {"body", "viewscope"}):
            continue
        if any(EVENT_RX.search(x.header) for x in f.frames_at(i) if x.kind == "other"):
            continue
        m = rx.search(c)
        if m:
            yield i, "%s constructed inside a view body (build once in a static let / memo)" % m.group(0).strip("( ")


def c09(f):  # synchronous system call in a view scope
    rx = re.compile(r"\b(UIImage\(data:|UIImage\(contentsOfFile|Data\(contentsOf:|String\(contentsOf:|FileManager\.default|SecItem(Copy|Add|Update|Delete)|UIPasteboard\.general|isSourceTypeAvailable|CGImageSourceCreate|NSKeyedUnarchiver)")
    for i, c in f.changed_lines():
        if "static let" in c or not f.in_scope(i, {"body", "viewscope"}):
            continue
        if any(EVENT_RX.search(x.header) for x in f.frames_at(i) if x.kind == "other"):
            continue
        m = rx.search(c)
        if m:
            yield i, "synchronous system call in a view body: " + m.group(0)


def c13(f):  # GeometryReader inside ForEach / List
    for i, c in f.changed_lines():
        if "GeometryReader" in c and any(re.search(r"\bForEach\s*\(|\bList\s*[\({]", x.header) for x in f.frames_at(i)):
            yield i, "GeometryReader inside ForEach/List: one per row (use onGeometryChange, written on change)"


def c15(f):  # Task inside onAppear
    rx = re.compile(r"\bTask\s*(\.detached)?\s*(\(.*\))?\s*\{")
    for i, c in f.changed_lines():
        if rx.search(c) and any(re.search(r"\.onAppear\b", x.header) for x in f.frames_at(i, rx)):
            yield i, "Task inside .onAppear is never cancelled (use .task / .task(id:))"


def c17(f):  # endless loop with no exit
    for i, c in f.changed_lines():
        if re.search(r"\bwhile\s+true\b", c):
            frame = next((x for x in f.enc[i] if x.open == i and re.search(r"\bwhile\s+true\b", x.header)), None)
            body = "\n".join(f.code[frame.open:frame.end + 1]) if frame else c
            if not re.search(r"\bbreak\b|\breturn\b|\bthrow\b|isCancelled|checkCancellation|try await", body):
                yield i, "`while true` with no break/return/throw/cancellation check (use `while !Task.isCancelled`)"


def c19(f):  # onChange(of:) on a scanning expression
    for i, c in f.changed_lines():
        for m in re.finditer(r"\.onChange\(of:", c):
            a = arg_of(c, m.end() - len("(of:"))
            a = a.split(",")[0] if "," in a and "{" not in a.split(",")[0] else a
            if re.search(r"\.(filter|sorted|reduce|compactMap|flatMap|joined|reversed|hashValue)\b|\.(contains|first)\(where", a):
                yield i, ".onChange(of:) on an expression that scans a collection: " + a.strip()[:60]


def c20(f):  # NSCache without both limits
    text = "\n".join(f.code)
    for i, c in f.changed_lines():
        if re.search(r"\bNSCache\s*<", c):
            missing = [k for k in ("countLimit", "totalCostLimit") if k not in text]
            if missing:
                yield i, "NSCache without " + " and ".join(missing)


def c21(f):  # withAnimation with a literal animation
    for i, c in f.changed_lines():
        if re.search(r"withAnimation\s*(\{|\(\s*\.|\(\s*Animation\.|\(\s*nil)", c):
            yield i, "withAnimation with a literal animation (use Motion.<token>.resolved(reduceMotion:))"


def c24(f):  # very large body
    for fr in f.frames:
        if fr.kind == "body" and fr.end - fr.open + 1 > 150 and any(fr.open <= x <= fr.end for x in f.changed):
            yield fr.open, "body is %d lines (limit 150): split it so unrelated state does not re-run all of it" % (fr.end - fr.open + 1)


def c27(f):  # probes left in
    if "/DesignSystem/Perf/" in f.rel:
        return
    for i, c in f.changed_lines():
        if re.search(r"PaseoPerf\.diff\(|\bPerfProbe\(", c):
            yield i, "PaseoPerf.diff / PerfProbe left in (remove once the cause is found)"
        elif "PaseoPerf.countNamed(" in c and "PaseoPerf.enabled" not in c and "PaseoPerf.enabled" not in f.code[i - 1] and not any("PaseoPerf.enabled" in x.header for x in f.frames_at(i)):
            yield i, "PaseoPerf.countNamed without an `if PaseoPerf.enabled` guard builds its string always"


def c28(f):
    if "/DesignSystem/Perf/" in f.rel:
        return
    for i, c in f.changed_lines():
        if re.search(r"(?<![.\w])(print|debugPrint|dump)\(|\bNSLog\(", c):
            yield i, "print/NSLog left in"


def c30(f):  # force unwrap
    for i in sorted(f.changed):
        s = f.skel[i]
        if not s.strip():
            continue
        s = re.sub(r"\b[A-Z]\w*!(?=\s*([\),{]|$))", "T", s)  # implicitly unwrapped types in signatures
        if re.search(r"\b(try|as)!|\bfatalError\(", s) or re.search(r"[A-Za-z0-9_\)\]]!(?!=)(?=\s*($|[\.\),\]\}:]|\s))", s):
            yield i, "force unwrap / try! / as! / fatalError (AGENTS rule 5)"


def c39(f):
    for i, c in f.changed_lines():
        if "CTFontManagerRegisterFontsForURL" in c:
            yield i, "CTFontManagerRegisterFontsForURL per font: register all in one CTFontManagerRegisterFontURLs call"


def c44(f):  # options measured and rejected (DECISIONS.md)
    text = "\n".join(f.code)
    for i, c in f.changed_lines():
        if re.search(r"shouldRasterize\s*=\s*true", c):
            yield i, "D05: shouldRasterize on a moving surface was rejected (visual risk)"
        if re.search(r"(windowSize|windowStep)\s*(:\s*\w+\s*)?=\s*[0-8]\b", c):
            yield i, "D01: a turn window of 8/8 or smaller was measured worse (2.5 to 4 s opens)"
        if re.search(r"NLTagger\(|NLLanguageRecognizer\(", c) and re.search(r"[Ww]arm", text):
            yield i, "D04: NLTagger/NLLanguageRecognizer warm-up had no effect on the first keyboard"
        if "becomeFirstResponder()" in c and re.search(r"[Ww]arm|[Pp]rewarm", text):
            yield i, "D03: a throwaway text field keyboard prewarm had no effect"
        if re.search(r"scrollTo\(edge:\s*\.bottom\)", c) and any(x.name == "repinOpen" for x in f.frames_at(i)):
            yield i, "D06: the open re-seat must land on a real row (scrollTo id: \"bottom\"), not the estimated edge"


def c45(f):
    for i, c in f.changed_lines():
        if re.search(r"\bObservableObject\b|@Published\b|@StateObject\b|@EnvironmentObject\b|@ObservedObject\b", c):
            yield i, "ObservableObject/@Published/@StateObject: any change re-runs every reader (use @Observable)"


def c47(f):
    for i, c in f.changed_lines():
        if re.search(r"\[[^\]\n]*\.\.\.[^\]\n]*\]\.count|\.dropFirst\([^)]*\)\.count", c):
            yield i, ".count on a suffix is O(n); inside a scan loop it is O(n^2)"


def c48(f):  # an array of every index, built per call
    rx = re.compile(r"\.indices\s*\.\s*(?:filter|map|compactMap|sorted)\b|\.enumerated\(\)\s*\.\s*(?:filter|map|compactMap)\b")
    for i, c in f.changed_lines():
        m = rx.search(c)
        if m:
            expr, root = receiver_root(c, m.start())
            yield i, "this materialises every index of `%s` on each call (%s): an O(n) array plus a closure per element. Search outward for the one index you need (FindNavigation.nearestIndex) or resolve it once per store change" % (expr or root, m.group(0).strip())


def asserts_value(cond, target):
    """True/False when `cond` proves the flag's value, None when it says nothing about it."""
    m = re.search(r"(!\s*)?" + re.escape(target) + r"\s*(?:==\s*(true|false))?", cond)
    if not m:
        return None
    base = True if not m.group(2) else m.group(2) == "true"
    return (not base) if m.group(1) else base


def guarded_flag(f, i, c, target, value):
    """True when an if/guard proves the flag is the opposite of `value`, so the write changes it."""
    want = value == "true"
    # a condition on the same line, or an enclosing if/guard header
    if re.search(r"\b(if|guard)\b", c) and asserts_value(c, target) not in (None, want):
        return True
    if re.search(r"\b(if|guard)\b[^{;]*(!=|==)[^{;]*\{", c):
        return True
    for fr in f.frames_at(i):
        h = fr.header
        if re.match(r"^\s*(?:if|guard)\b", h):
            if re.search(r"!=|==", h):
                return True
            got = asserts_value(h, target)
            if got is not None and got != want:
                return True
    # a prior guard inside the same function: after it the value is known
    for fr in f.frames_at(i):
        if fr.kind != "func":
            continue
        for k in range(i - 1, fr.open, -1):
            if re.search(r"(?<![\w.])" + re.escape(target) + r"\s*=[^=]", f.code[k]):
                break
            if re.match(r"^\s*guard\b", f.code[k]):
                got = asserts_value(f.code[k], target)
                if got is not None and got != want:
                    return True
    return False


def c49(f):  # an observed flag written with a literal, not compare-first
    rx = re.compile(r"(?<![\w.])((?:self|[a-z]\w*(?:\.[a-z]\w*)*)\.)?([a-z]\w*)\s*=\s*(true|false)\b")
    for i, c in f.changed_lines():
        if not any(x.kind == "func" for x in f.frames_at(i)):
            continue
        if any(x.kind in ("body", "viewscope", "init") for x in f.frames_at(i)):
            continue
        if any(x.name in ("updateUIView", "updateUIViewController") for x in f.frames_at(i) if x.kind == "func"):
            continue  # H15 owns the representable update path
        for m in rx.finditer(c):
            recv, prop = (m.group(1) or "").rstrip("."), m.group(2)
            if re.search(r"\b(?:let|var|case)\s+" + re.escape(prop) + r"\b", c):
                continue
            if recv:
                root = recv.split(".")[0]
                if root == "self" or root not in MODEL_ROOTS:
                    continue
                target = recv + "." + prop
            else:
                t = f.enclosing_type(i)
                if not t or "@Observable" not in t.conforms:
                    continue
                target = prop
            if guarded_flag(f, i, c, target, m.group(3)):
                continue
            yield i, "`%s = %s` writes an observed flag with a literal and no compare: every @Observable set notifies its readers even when the value is unchanged. Write `if %s` / `if !%s` around it (Apple: only update when the change is meaningful; C49, M42)" % (target, m.group(3), target, target)



# --------------------------------------------------------------------------------------------------
# MANUAL heuristics: a hit is a question with file:line, never a failure.
# --------------------------------------------------------------------------------------------------


def stable_expr(expr):
    e = expr.strip()
    if e.startswith('"'):
        inner = e.strip('"')
        interp = re.findall(r"\\\((.*?)\)", inner)
        return all(stable_expr(x) for x in interp)
    return bool(re.search(r"(^|\.)(id|ID|seqStart|rawValue)$|\w(Id|ID)$", e))


def h_id_other(f):
    for i, c in f.changed_lines():
        for m in re.finditer(r"\.id\(", c):
            if "Color.clear" in c:
                continue
            a = arg_of(c, m.end() - 1)
            if a and not stable_expr(a) and not re.search(r"seqEnd|UUID\(\)|Date|hashValue|\.count|\.text", a):
                yield i, ".id(%s)" % a.strip()[:50]
        if re.search(r"ForEach\(.*id:\s*\\\.(self|offset)\b", c):
            yield i, "ForEach id: \\.self or \\.offset"


def h_binding_body(f):
    for i, c in f.changed_lines():
        m = re.search(r"Binding\(\s*get:(.*)", c)
        if m and STORE_NAMES.search(m.group(1)) and f.in_scope(i, {"body", "viewscope"}) and not f.in_scope(i, {"init"}):
            yield i, "Binding(get:) reads a store inside a view body"


def h_row_noneq(f):
    for i, c in f.changed_lines():
        m = re.search(r"\bstruct\s+(\w*(Row|Cell)\w*)\s*:([^{]*)", c)
        if m and re.search(r"\bView\b", m.group(3)) and "Equatable" not in m.group(3):
            yield i, "%s is a View but not Equatable" % m.group(1)


def h_anyview(f):
    if "/Shell/" in f.rel:
        return
    for i, c in f.changed_lines():
        if re.search(r"AnyView\(|->\s*AnyView", c):
            yield i, "AnyView"


CHAIN_RX = re.compile(r"\.(sorted|filter|reduce|flatMap|compactMap|map)\b")


def chain_hit(c):
    """(receiver expression, method) for the first chain over a collection on this line, else None."""
    for m in CHAIN_RX.finditer(c):
        expr, root = receiver_root(c, m.start())
        if not root or root in ITEM_ROOTS:
            continue  # one item's rows or pieces: bounded by the item, not by the conversation
        if root in COLLECTION_ROOTS or re.search(r"\b(store|session|controller|timeline|conversation|directory)\b", expr):
            return expr, m.group(1)
    return None


def h_chain(f):
    for i, c in f.changed_lines():
        scope = f.in_scope(i, {"body", "viewscope"})
        if not scope:
            t = f.enclosing_type(i)
            comp = any(x.kind == "computed" for x in f.enc[i])
            if not (t and "View" in t.conforms and comp):
                continue
        if "static let" in c or re.search(r"[mM]emo|[cC]ache", c) or any(EVENT_RX.search(x.header) for x in f.frames_at(i) if x.kind == "other"):
            continue
        hit = chain_hit(c)
        if hit:
            yield i, "sort/filter/map over `%s` in a body or computed property: it is rebuilt on every pass; build it once in the store or a memo (M16)" % hit[0]


def h_construct2(f):
    rx = re.compile(r"Calendar\.current|AttributedString\(|NSAttributedString\(|UserDefaults\.standard|UIImage\(named:|Image\(uiImage")
    for i, c in f.changed_lines():
        if "static let" in c or not f.in_scope(i, {"body", "viewscope"}):
            continue
        if any(EVENT_RX.search(x.header) for x in f.frames_at(i) if x.kind == "other"):
            continue
        m = rx.search(c)
        if m:
            yield i, m.group(0) + " in a view body"


def h_geometry(f):
    for i, c in f.changed_lines():
        if "GeometryReader" in c and not any(re.search(r"\bForEach\s*\(|\bList\s*[\({]", x.header) for x in f.frames_at(i)):
            yield i, "GeometryReader"


def h_mainasync(f):
    for i, c in f.changed_lines():
        if re.search(r"DispatchQueue\.main\.(async|asyncAfter|sync)", c):
            yield i, "DispatchQueue.main hop"


def h_task(f):
    rx = re.compile(r"\bTask\s*(\.detached)?\s*(\(.*\))?\s*\{")
    for i, c in f.changed_lines():
        if rx.search(c):
            outer = f.frames_at(i, rx)
            if any(f_.kind in ("body", "viewscope") for f_ in outer) and not any(EVENT_RX.search(x.header) for x in outer if x.kind == "other") and not any(re.search(r"\.onAppear", x.header) for x in outer):
                yield i, "Task started directly in a view body"
            elif re.search(r"=\s*Task\b", c) and not any(".cancel()" in x for x in f.code):
                yield i, "stored Task and no .cancel() in this file"
        if re.search(r"\.task\s*\{|\.task\(priority:[^)]*\)\s*\{", c):
            yield i, ".task without id"


def h_timer(f):
    for i, c in f.changed_lines():
        if re.search(r"Timer\.(scheduledTimer|publish)|CADisplayLink\(|TimelineView\(\s*\.animation|\.repeatForever|\.autoconnect\(\)", c):
            yield i, "timer / display link / endless animation"


def h_onchange_coll(f):
    for i, c in f.changed_lines():
        if re.search(r"\.onChange\(of:\s*[\w\.]*\." + BIG + r"\s*[,)]|\.onChange\(of:[^{]*\.map\(", c):
            yield i, ".onChange(of:) on a whole collection"


def h_dict_cache(f):
    text = "\n".join(f.code)
    bounded = re.search(r"removeAll|evict|countLimit|\blimit\b|capacity|budget|removeValue|removeFirst", text)
    for i, c in f.changed_lines():
        if re.search(r"\b(var|let)\s+\w*([cC]ache|[mM]emo|[mM]emoized)\w*\s*(:[^=]*)?=\s*(\[[^\]]*:[^\]]*\]\(\)|\[:\]|Dictionary<)", c) and not bounded:
            yield i, "dictionary cache with no limit or eviction in this file"
        if re.search(r"\bstatic\s+var\s+\w+\s*:\s*\[[^\]]*:[^\]]*\]\s*=\s*\[:\]", c) and not bounded:
            yield i, "static dictionary with no limit or eviction in this file"


def h_env_body(f):
    seen = set()
    for i in sorted(f.changed):
        t = f.enclosing_type(i)
        if t and id(t) not in seen and "View" in t.conforms:
            seen.add(id(t))
            n = sum(1 for k in range(t.open, t.end + 1) if "@Environment(" in f.code[k])
            if n >= 7:
                yield t.open, "%s reads %d environment values: each one makes it a dependency of every change to them; read each value in the child that draws it (M01)" % (t.name, n)


def guarded(f, i, c):
    if re.search(r"\b(if|guard)\b.*(!=|==)|!=", c):
        return True
    j = i - 1
    while j >= 0 and not f.code[j].strip():
        j -= 1
    if j >= 0 and re.search(r"^\s*(if|guard)\b.*(!=|==)|^\s*}?\s*else\b", f.code[j]):
        return True
    return any(re.search(r"\b(if|guard)\b.*(!=|==)", x.header) for x in f.frames_at(i))


def h_repr(f):
    for i, c in f.changed_lines():
        m = re.search(r"\bstruct\s+(\w+)\s*:([^{]*)", c)
        if m and re.search(r"UIView(Controller)?Representable", m.group(2)) and "Equatable" not in m.group(2):
            yield i, "%s is a representable but not Equatable" % m.group(1)
    for fr in f.frames:
        if fr.kind == "func" and fr.name in ("updateUIView", "updateUIViewController"):
            pm = re.search(r"update\w+\(\s*_\s+(\w+)\s*:", fr.header)
            pname = pm.group(1) if pm else "uiView"
            for i in range(fr.open + 1, fr.end + 1):
                if i not in f.changed:
                    continue
                c = f.code[i]
                if re.match(r"^\s*%s\.\w+(\.\w+)*\s*=[^=]" % re.escape(pname), c) and not guarded(f, i, c):
                    yield i, "update assigns %s property without comparing first" % pname


def h_store_write(f):
    if "/PaseoStore/" not in f.rel:
        return
    stored = set()
    for i, c in enumerate(f.code):
        m = re.match(r"^\s*(?:@\w+\s+)*(?:(?:public|private|internal|fileprivate)(?:\(set\))?\s+)*var\s+(\w+)\b", c)
        t = f.enclosing_type(i)
        if m and t and f.enc[i] and f.enc[i][-1] is t and "@ObservationIgnored" not in c:
            stored.add(m.group(1))
    for i, c in f.changed_lines():
        if not any(x.kind == "func" for x in f.frames_at(i)):
            continue
        m = re.match(r"^\s*(?:self\.)?(\w+)(\[[^\]]+\])?\s*=\s*[^=]", c)
        if m and m.group(1) in stored and not guarded(f, i, c):
            yield i, "%s assigned without comparing to the held value" % m.group(1)
            continue
        m = re.match(r"^\s*(?:self\.)?(\w+)\.sort\b", c)
        if m and m.group(1) in stored:
            yield i, "in-place sort of stored %s notifies even when nothing moved" % m.group(1)


def h_main_io(f):
    rx = re.compile(r"Data\(contentsOf|String\(contentsOf|\.write\(to:|FileManager\.default\.(createDirectory|contentsOfDirectory|removeItem|copyItem|moveItem|attributesOfItem)")
    for i, c in f.changed_lines():
        m = rx.search(c)
        if not m or f.in_scope(i, {"body", "viewscope"}):
            continue
        t = f.enclosing_type(i)
        if not t or t.name and re.search(r"\bactor\b", f.skel[t.open]):
            continue
        if not (t.mainactor or "View" in t.conforms or "@Observable" in f.skel[max(t.open - 2, 0)] + f.skel[t.open]):
            continue
        if any(re.search(r"detached|DispatchQueue|\.async|nonisolated|queue", x.header) for x in f.frames_at(i)):
            continue
        yield i, m.group(0) + " on a main-actor type"


def h_stream(f):
    for i, c in f.changed_lines():
        if ".unbounded" in c:
            yield i, "unbounded stream buffer"


def h_lazy(f):
    for i, c in f.changed_lines():
        if re.search(r"\bScrollView\b", c):
            for j in range(i + 1, min(i + 10, len(f.code))):
                if re.search(r"\b(V|H)Stack\b", f.code[j]) and "Lazy" not in f.code[j]:
                    if any(re.search(r"\bForEach\(", f.code[k]) for k in range(j, min(j + 14, len(f.code)))):
                        yield i, "ScrollView { VStack { ForEach } }"
                    break


def h_offscreen(f):
    tags = path_tags(f.rel)
    if not tags & {"stream", "row", "shell", "media"}:
        return
    for i, c in f.changed_lines():
        if re.search(r"\.(mask|blur|drawingGroup|compositingGroup|shadow)\(", c):
            yield i, "offscreen-pass effect in a hot area"


def h_img(f):
    for i, c in f.changed_lines():
        if re.search(r"AsyncImage\(", c) or (re.search(r"UIImage\(data:", c) and not f.in_scope(i, {"body", "viewscope"})):
            yield i, "image loaded outside the media pipeline"


def h_web(f):
    if "/Rich/" in f.rel:
        return
    for i, c in f.changed_lines():
        if re.search(r"WKWebView\(|LPLinkView\(|WKWebViewConfiguration\(", c):
            yield i, "web view outside Rich/"


def h_launch(f):
    if not f.rel.startswith("App/"):
        return
    rx = re.compile(r"Keychain|SecItem|UserDefaults|FileManager|JSONDecoder|URLSession|Data\(contentsOf|CTFontManager|NLTagger|Bundle\.main\.url")
    for i, c in f.changed_lines():
        if rx.search(c) and any(x.kind == "init" or "@main" in x.header for x in f.frames_at(i)):
            yield i, "launch-path work in an init"


def h_sendable(f):
    text = "\n".join(f.code)
    for i, c in f.changed_lines():
        if "@unchecked Sendable" in c and not re.search(r"NSLock|OSAllocatedUnfairLock|os_unfair_lock|DispatchQueue|Mutex", text):
            yield i, "@unchecked Sendable with no lock in this file"


def h_envclosure(f):
    for i, c in f.changed_lines():
        if re.search(r"\.environment\(\s*\\\.\w+\s*,\s*(\{|\w+\s*\{)", c):
            yield i, "closure literal put in the environment"


def h_gesture(f):
    for i, c in f.changed_lines():
        if "DragGesture(" in c:
            yield i, "DragGesture (finger-tracked motion belongs in UIKit)"


def h_scrolljump(f):
    if "/Transcript/" not in f.rel:
        return
    for i, c in f.changed_lines():
        if re.search(r"scrollTo\(|\.scrollPosition\(|defaultScrollAnchor|\bwindow(Size|Step)\b", c):
            yield i, "scroll target or turn window changed: land on a real row id, use bounded hops, and end the re-seat on the reader's action (PATTERNS/lazy-stacks-and-scrolling.md sections 2 to 4, M21)"


def scan_calls(c):
    """Linear scans that return an element or filter a collection (not `prefix`/`drop`, which are O(1))."""
    for m in re.finditer(r"\.(first|firstIndex|last|lastIndex|contains|allSatisfy|filter)\s*([({])", c):
        if m.group(2) == "(" and not re.match(r"\s*where\s*:", c[m.end():]):
            continue
        yield m


def h_scan(f):  # H29: a scan in a helper that a body or a callback may reach
    seen = {}
    for i, c in f.changed_lines():
        if f.in_scope(i, {"body", "viewscope"}):
            continue  # H05 owns body and view-scope chains
        for m in scan_calls(c):
            expr, root = receiver_root(c, m.start())
            if not root or root in ITEM_ROOTS or root not in COLLECTION_ROOTS:
                continue
            if expr.endswith(".indices"):
                continue  # C48 owns an array built from every index
            small = re.search(r"\.(?:prefix|suffix)\(\s*(\d+)\s*\)", expr)
            if small and int(small.group(1)) <= 64:
                continue  # bounded by a literal: the scan is over at most 64 rows
            name = symbol_at(f, i)
            key = (name, root)
            seen[key] = seen.get(key, 0) + 1
            if seen[key] > 2:
                continue
            yield i, "linear scan of `%s` in `%s`: O(n) on every call. If a body pass, a scroll or geometry callback, or a tick can reach it, binary-search the timeline-ordered array or resolve the index once per store change (FindNavigation.firstTurnIndex). If it runs once per user action, answer M18 with that" % (expr, name)


def h_own_task(f):  # H30: a task started from a method with no handle
    rx = re.compile(r"(?<![\w.])Task(?:\.detached)?(?:\s*\([^)]*\))?\s*\{")
    for i, c in f.changed_lines():
        m = rx.search(c)
        if not m:
            continue
        before = c[:m.start()].rstrip()
        if before.endswith("=") or re.search(r"\breturn$", before):
            continue
        frames = [x for x in f.frames_at(i) if not (x.open == i and re.search(r"\bTask\b", x.header))]
        if not any(x.kind == "func" for x in frames):
            continue
        if any(x.kind in ("body", "viewscope", "init") for x in frames):
            continue
        if any(x.kind == "other" and EVENT_RX.search(x.header) for x in frames):
            continue
        yield i, "`Task` started in `%s` and discarded: if a newer call, a close, or a disappear can supersede it, keep the handle and cancel it (TranscriptJumpRunner.runAfterFetch; TEMPLATES/task.swift.md)" % symbol_at(f, i)


def geo_spans(f):
    """Character spans of geometry callbacks, including the `action:` closure after the value closure
    (`.onGeometryChange(for:) { ... } action: { ... }` closes the first frame before the second opens)."""
    full = "\n".join(f.code)
    starts, pos = [], 0
    for ln in f.code:
        starts.append(pos)
        pos += len(ln) + 1
    spans = []
    for m in GEO_RX.finditer(full):
        b = full.find("{", m.end())
        if b < 0:
            continue
        depth, j, groups = 0, b, 0
        while j < len(full):
            if full[j] == "{":
                depth += 1
            elif full[j] == "}":
                depth -= 1
                if depth == 0:
                    groups += 1
                    k = j + 1
                    while k < len(full) and full[k] in " \t\r\n,":
                        k += 1
                    if groups == 1 and full.startswith("action:", k):
                        j = full.find("{", k)
                        if j < 0:
                            break
                        depth = 0
                        continue
                    break
            j += 1
        spans.append((b, min(j, len(full) - 1), starts))
    return [(s, e, st) for s, e, st in spans]


def line_in_span(starts, i, span):
    pos = starts[i]
    return span[0] <= pos <= span[1]


def h_geo_dict(f):  # H31: a dictionary written from a geometry callback
    dicts = set()
    for i, c in enumerate(f.code):
        m = re.match(r"^\s*(?:@\w+\s+)*(?:(?:private|fileprivate|internal|public)(?:\(set\))?\s+)*var\s+(\w+)\s*:\s*\[[^\]]+\]\s*(?:=|$)", c)
        if m and f.enclosing_type(i) is f.enc[i][-1]:
            dicts.add(m.group(1))
    if not dicts:
        return
    writers = {}
    for fr in f.frames:
        if fr.kind != "func":
            continue
        for prop in dicts:
            for k in range(fr.open, fr.end + 1):
                if re.search(r"(?:^|[^\w.])%s\s*\[[^\]]*\]\s*=(?!=)" % re.escape(prop), f.code[k]):
                    writers.setdefault(fr.name, (prop, k))
                    break
    if not writers:
        return
    spans = geo_spans(f)
    if not spans:
        return
    seen = set()
    for span in spans:
        for name, (prop, write_line) in writers.items():
            call = re.compile(r"(?:^|[^\w])%s\s*\(" % re.escape(name))
            calls = [j for j in range(len(f.code)) if line_in_span(span[2], j, span) and call.search(f.code[j])]
            if not calls:
                continue
            target = next((j for j in calls if j in f.changed), None)
            if target is None:
                if write_line not in f.changed:
                    continue
                target = write_line
            key = (span[0], name)
            if key in seen:
                continue
            seen.add(key)
            yield target, "`%s` writes the dictionary `%s` from a geometry/scroll callback: a per-frame path must not hash into a growing table; if only the latest report matters keep one slot (FindRowProbe.lastReport), and if per-key data is needed write only when the value changed" % (name, prop)


AUTO = {
    "C01": (c01, "M08", "PF-3", "identity-and-streaming", ".id() with a changing value"),
    "C03": (c03, "M02", "PF-18", "observation-and-invalidation", "Binding(get:) on a store in an init"),
    "C04": (c04, "M03", "PF-2", "observation-and-invalidation", "object created in a @State default"),
    "C06": (c06, "M10", "PF-4", "rows-and-lists", "closure stored in a Row/Cell"),
    "C08": (c08, "M15", "PF-6", "concurrency-and-main-thread", "formatter/regex/coder built in a body"),
    "C09": (c09, "M15", "PF-6", "concurrency-and-main-thread", "synchronous system call in a body"),
    "C13": (c13, "M13", "PF-30", "media-and-images", "GeometryReader inside ForEach/List"),
    "C15": (c15, "M23", "PF-36", "concurrency-and-main-thread", "Task inside .onAppear"),
    "C17": (c17, "M24", "PF-36", "concurrency-and-main-thread", "while true"),
    "C19": (c19, "M19", "PF-8", "observation-and-invalidation", "onChange(of:) on a scan"),
    "C20": (c20, "M28", "PF-31", "caches-and-memory", "NSCache without both limits"),
    "C21": (c21, "M36", "R-4", "animation-and-drawer", "literal withAnimation"),
    "C24": (c24, "M19", "PF-24", "observation-and-invalidation", "body over 150 lines"),
    "C27": (c27, "M38", "PF-22", "launch-and-startup", "probe left in"),
    "C28": (c28, "M38", "PF-40", "launch-and-startup", "print left in"),
    "C30": (c30, "M38", "AGENTS-5", "stores-and-core", "force unwrap"),
    "C39": (c39, "M32", "PF-35", "launch-and-startup", "per-font registration"),
    "C44": (c44, "M22", "PF-41", "lazy-stacks-and-scrolling", "rejected option"),
    "C45": (c45, "M06", "PF-39", "observation-and-invalidation", "ObservableObject/@Published"),
    "C47": (c47, "M17", "PF-21", "text-markdown-code", ".count on a suffix"),
    "C48": (c48, "M41", "PF-21", "hot-paths-and-indexing", "an array of every index, built per call"),
    "C49": (c49, "M42", "PF-25", "hot-paths-and-indexing", "an observed flag written without a compare"),
}

# (function, MUST item, what to verify: printed once per item; each hit adds the file:line)
HEUR = {
    "H01": (h_id_other, "M09", ".id/ForEach id: is it a stable entity id (seq:<seqStart>, agentId) that survives every state of the item, not an offset or a streaming value?"),
    "H02": (h_binding_body, "M01", "Binding(get:) reading a store inside a body: does the parent now depend on that field for nothing?"),
    "H03": (h_row_noneq, "M11", "Row/Cell view not Equatable: will SwiftUI run its body for every parent pass?"),
    "H04": (h_anyview, "M11", "AnyView in repeated content: it erases the type, so the child is rebuilt instead of compared"),
    "H05": (h_chain, "M16", "sort/filter/map over a store collection in a body or computed property: is it built once per pass (store or memo) and not per row?"),
    "H06": (h_construct2, "M18", "a costly constructor or default read in a body: build it once (static let / memo) and pass it in"),
    "H07": (h_geometry, "M14", "GeometryReader: does each row reserve its size and read width with onGeometryChange written on change?"),
    "H08": (h_mainasync, "M25", "DispatchQueue.main hop from main-actor code: it only delays the work a runloop turn"),
    "H09": (h_task, "M25", "Task/.task lifecycle: is it keyed by .task(id:), cancelled on disappear, and never one per row?"),
    "H10": (h_timer, "M37", "timer, display link or endless animation: does it stop when obscured, asleep, or reduce-motion is on?"),
    "H11": (h_onchange_coll, "M01", "onChange(of:) on a whole collection: does every element change re-run the action?"),
    "H12": (h_dict_cache, "M29", "dictionary cache without a limit or eviction in this file: what bounds its count and cost?"),
    "H14": (h_env_body, "M01", "many environment reads or a very large body: which of these does the body actually draw, and which belong to a child?"),
    "H15": (h_repr, "M34", "representable update: is it Equatable, and does every assignment compare first?"),
    "H16": (h_store_write, "M04", "store property written without a compare, or sorted in place: can the value repeat (push, poll, reconnect)?"),
    "H17": (h_main_io, "M26", "file I/O on a main-actor type: can it move to a serial queue with a value snapshot?"),
    "H18": (h_stream, "M30", "unbounded stream buffer: use .bufferingNewest(n)"),
    "H19": (h_lazy, "M12", "ScrollView { VStack { ForEach } }: can the list exceed 30 items? Then it must be lazy or windowed"),
    "H20": (h_offscreen, "M18", "mask/blur/shadow/drawingGroup in repeated content: each one adds an offscreen pass per row"),
    "H21": (h_img, "M18", "image loaded outside the media pipeline: decode at the drawn size, off main"),
    "H22": (h_web, "M31", "web view outside Rich/: is it lazy or warmed at idle, never in init or the open path?"),
    "H23": (h_launch, "M33", "launch-path work in an init: is it on the first-frame list (defaults, one font call, the shell)?"),
    "H24": (h_sendable, "M29", "@unchecked Sendable with no lock in this file: what protects it?"),
    "H25": (h_envclosure, "M07", "closure literal in the environment: a non-comparable value re-runs every reader; use an observable flag object"),
    "H26": (h_gesture, "M35", "DragGesture: finger-tracked motion belongs in a UIKit pan, and SwiftUI learns only open/closed"),
    "H27": (h_scrolljump, "M21", "transcript scroll or window code: verify the target is a real row id, the hops are bounded, and the re-seat ends on the reader's action"),
    "H29": (h_scan, "M18", "a linear scan in a helper: is it reachable from a body pass, a scroll/geometry callback or a tick? Then it must be O(log n) or resolved once"),
    "H30": (h_own_task, "M25", "a Task started from a method with no stored handle: can a newer call, a close or a disappear supersede it?"),
    "H31": (h_geo_dict, "M18", "a dictionary written from a geometry/scroll callback: a per-frame report must overwrite one value and compare first"),
}
SET_LEVEL_HEUR = {"H28": ("M40", "core store changed and no test file changed")}

# --------------------------------------------------------------------------------------------------
# Docs: MUST.md, MANUAL.md
# --------------------------------------------------------------------------------------------------


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def parse_must():
    items = {}
    for ln in read(os.path.join(PERF, "MUST.md")).split("\n"):
        m = re.match(r"^- (M\d+) \[(AUTO|MANUAL)([^\]]*)\]\s*(.*)$", ln)
        if m:
            items[m.group(1)] = {"tag": m.group(2), "checks": m.group(3).split(), "text": m.group(4).strip()}
    return items


def parse_manual():
    items, cur = {}, None
    for ln in read(os.path.join(PERF, "MANUAL.md")).split("\n"):
        m = re.match(r"^### (M\d+)\b", ln)
        if m:
            cur = m.group(1)
            items[cur] = {}
            continue
        m = re.match(r"^\*\*(Ask|If no or unsure|Re-read):\*\*\s*(.*)$", ln)
        if m and cur:
            items[cur][m.group(1)] = m.group(2).strip()
    return items


# --------------------------------------------------------------------------------------------------
# Analysis
# --------------------------------------------------------------------------------------------------


def analyse(files):
    """files: list of SwiftFile. Returns dict of results."""
    res = {"auto": [], "hits": [], "waived": [], "features": {}, "tags": {}}
    for f in files:
        tags = path_tags(f.rel)
        res["tags"][f.rel] = tags
        if "test" in tags:
            continue
        feats = set()
        for i, c in f.changed_lines():
            for fid, rx in FEATURE_RX.items():
                if rx.search(c):
                    feats.add(fid)
        res["features"][f.rel] = feats
        for cid, (fn, m, rule, pat, title) in AUTO.items():
            for i, msg in fn(f):
                w = f.waiver(i, cid)
                (res["waived"] if w else res["auto"]).append((cid, f.rel, i + 1, msg, w))
        for hid, (fn, m, title) in HEUR.items():
            for i, msg in fn(f):
                w = f.waiver(i, hid)
                (res["waived"] if w else res["hits"]).append((hid, f.rel, i + 1, msg, w))
    # set-level: core store sources changed with no test file in the change
    core = [f for f in files if "core" in path_tags(f.rel) and "/PaseoStore/" in f.rel and f.changed]
    if core and not any("test" in path_tags(f.rel) for f in files):
        f = core[0]
        first = sorted(f.changed)[0]
        res["hits"].append(("H28", f.rel, first + 1, "no test file in this change", None))
    return res


def build_manual(res, must, manual):
    """item id -> {why, lines, hints, area, triggered}. Area items apply to the paths; triggered items
    also have a heuristic hit with a file:line and a sentence saying what to verify."""
    out = {}

    def add(mid, why=None, area=None):
        e = out.setdefault(mid, {"why": [], "lines": [], "hints": [], "area": [], "triggered": False})
        if why and why not in e["why"]:
            e["why"].append(why)
        if area and area not in e["area"]:
            e["area"].append(area)

    for rel, feats in res["features"].items():
        for fid in sorted(feats):
            name = next(x[1] for x in FEATURES if x[0] == fid)
            for mid in next(x[3] for x in FEATURES if x[0] == fid):
                if must.get(mid, {}).get("tag") == "MANUAL":
                    add(mid, "%s: %s" % (fid, name.split(" (")[0]))
        for t in sorted(res["tags"][rel] & set(PATH_ITEMS)):
            for mid in PATH_ITEMS[t]:
                if must.get(mid, {}).get("tag") == "MANUAL":
                    add(mid, area=t)
    for hid, rel, line, msg, _ in res["hits"]:
        mid = HEUR[hid][1] if hid in HEUR else SET_LEVEL_HEUR[hid][0]
        add(mid, "hit %s" % hid)
        e = out[mid]
        e["triggered"] = True
        if (rel, line, msg) not in e["lines"]:
            e["lines"].append((rel, line, msg))
        verify = HEUR[hid][2] if hid in HEUR else "no test file changed: a store change needs a test (M40)"
        hint = next((h for h in e["hints"] if h[0] == hid), None)
        if hint is None:
            hint = [hid, verify, []]
            e["hints"].append(hint)
        if (rel, line) not in hint[2]:
            hint[2].append((rel, line))
    if any(t & {"ui", "core"} for rel, t in res["tags"].items() if "test" not in t):
        add("M40", "any UI/Core change")
    return out


def features_for(res):
    return {rel: sorted(v) for rel, v in res["features"].items()}


# Which patterns to read first, per path tag. Chosen for the diff, so a small agent does not open the
# whole Performance/ tree before its first edit.
TAG_PATTERNS = {
    "stream": ["lazy-stacks-and-scrolling", "identity-and-streaming", "hot-paths-and-indexing"],
    "row": ["rows-and-lists", "identity-and-streaming", "hot-paths-and-indexing"],
    "composer": ["uikit-interop-and-keyboard", "hot-paths-and-indexing"],
    "shell": ["animation-and-drawer", "hot-paths-and-indexing"],
    "media": ["media-and-images"],
    "store": ["stores-and-core", "hot-paths-and-indexing"],
    "launch": ["launch-and-startup"],
    "lists": ["rows-and-lists", "lazy-stacks-and-scrolling"],
}


def read_block(res):
    tags = set()
    for _, t in res["tags"].items():
        tags |= (t - {"test"})
    pats = []
    for tag in ("stream", "row", "composer", "shell", "media", "store", "launch", "lists"):
        if tag in tags:
            for p in TAG_PATTERNS[tag]:
                if p not in pats:
                    pats.append(p)
    items = sorted({m for t in tags for m in PATH_ITEMS.get(t, [])})
    out = ["== 0. READ THIS FIRST (chosen from the paths in this diff; the rest is reference) =="]
    out.append("  1. Performance/FINAL-CHECK.md: the procedure and what ESCALATE means (1 minute).")
    out.extend(wrap_line("  2. Performance/MUST.md section B, only these lines: ", " ".join(items) or "(none)"))
    if pats:
        out.extend(wrap_line("  3. Before editing: ", ", ".join("Performance/PATTERNS/%s.md" % p for p in pats[:3])))
    out.append("  When a check fires: Performance/CHECKS.md (what it means and the fix), MANUAL.md, PATTERNS/.")
    out.append("  Long reference, open only on demand: RULES.md, DECISIONS.md, CATALOG.md, BUDGETS.md, GLOSSARY.md.")
    return out


def wrap_line(prefix, text, width=110, cont=None):
    """prefix + text wrapped to `width`, continuation indented to the prefix (or `cont`)."""
    out, cur = [], ""
    for w in text.split():
        if not cur:
            cur = w
        elif len(prefix) + len(cur) + 1 + len(w) <= width:
            cur += " " + w
        else:
            out.append(prefix + cur)
            prefix, cur = (cont if cont is not None else " " * len(prefix)), w
    if cur:
        out.append(prefix + cur)
    return out


def wrap_rule(text, width=94, indent="         "):
    words, lines, cur = text.split(), [], ""
    for w in words:
        if not cur:
            cur = w
        elif len(cur) + 1 + len(w) <= width:
            cur += " " + w
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return ("\n" + indent).join(lines)


VERDICT_LINE_RX = re.compile(r"^\s*\[( |x|X)\]\s+(.+)$")


def verdict_from_signoff(text):
    """('DONE'|'DONE WITH ESCALATIONS'|'NOT DONE', reason) from a pasted SIGN-OFF block."""
    items = []
    for ln in text.split("\n"):
        m = VERDICT_LINE_RX.match(ln)
        if m:
            items.append((m.group(1).strip(), ln.strip()))
    if not items:
        return "NOT DONE", "the sign-off has no [ ] item lines"
    unticked = [ln for tick, ln in items if tick == "" and "ESCALATE:" not in ln]
    escalated = [ln for _, ln in items if "ESCALATE:" in ln] + [
        ln.strip() for ln in text.split("\n") if not VERDICT_LINE_RX.match(ln) and ln.strip().startswith("ESCALATE:")]
    if unticked:
        return "NOT DONE", "%d line(s) neither ticked nor escalated (first: %s)" % (len(unticked), unticked[0][:80])
    if escalated:
        return "DONE WITH ESCALATIONS", str(len(escalated))
    return "DONE", ""


# --------------------------------------------------------------------------------------------------
# Git plumbing
# --------------------------------------------------------------------------------------------------


def git(*args, cwd=REPO):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return p.stdout


def resolve_base(base):
    """(ref, merge-base, where the ref came from). An explicit ref wins; else the branch's upstream; else
    origin/main, main, origin/foundation, foundation."""
    if base:
        cands, source = [base], "given on the command line"
    else:
        up = git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}").strip()
        up = up if up and not up.startswith("HEAD") else ""
        cands = ([up] if up else []) + ["origin/main", "main", "origin/foundation", "foundation"]
        source = "the branch's upstream" if up else "origin/main, else foundation"
    for c in cands:
        if c and subprocess.run(["git", "rev-parse", "--verify", "-q", c + "^{commit}"], cwd=REPO, capture_output=True).returncode == 0:
            mb = git("merge-base", c, "HEAD").strip()
            return c, mb or c, source
    return None, None, source


SCOPE_RX = re.compile(r"^(?!.*/paseo-probe/)(Packages/(PaseoUI|PaseoCore)/Sources/|App/).*\.swift$")


def changed_from_git(base):
    ref, mb, source = resolve_base(base)
    files = {}
    names = git("diff", "--name-only", "--diff-filter=ACMR", "-M", mb, "--").split("\n")
    names += git("ls-files", "-o", "--exclude-standard").split("\n")
    allnames = [n for n in dict.fromkeys(names) if n]
    tests = [n for n in allnames if n.endswith(".swift") and "/Tests/" in n and n.startswith("Packages/")]
    for n in allnames:
        if not n.endswith(".swift") or not SCOPE_RX.match(n) or not os.path.exists(os.path.join(REPO, n)):
            continue
        in_base = subprocess.run(["git", "cat-file", "-e", "%s:%s" % (mb, n)], cwd=REPO, capture_output=True).returncode == 0
        lines = None  # a file new since the base is checked in full
        if in_base:
            diff = git("diff", "-U0", "--no-color", mb, "--", n)
            lines = set()
            for m in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", diff, re.M):
                start, cnt = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
                lines.update(range(start, start + cnt))
        files[n] = lines
    return ref, mb, {"files": files, "tests": tests, "source": source}


# --------------------------------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------------------------------


def where_lines(lines):
    """At most three `file:line` locations, then '+N more' (a hit list is a pointer, not a dump)."""
    shown = ["%s:%d" % (os.path.basename(rel), line) for rel, line, _ in lines]
    more = len(shown) - 3
    return ", ".join(shown[:3]) + ("  (+%d more)" % more if more > 0 else "")


def render(res, must, manual, meta):
    out = []
    failed_ids = {a[0] for a in res["auto"]}
    out.append("final-check  base=%s (%s)  swift files=%d  (%s)%s" % (
        meta["base"], meta.get("source", "?"), len(res["tags"]), meta["mode"],
        "  NO CHANGES since the base" if meta.get("empty") else ""))
    out.append("This script guarantees only the AUTO-VERIFIED list below (exact patterns on your changed lines).")
    out.append("It never claims anything about timing or semantics: blocks 3 and 4 are yours to answer.")
    out.append("")
    out.extend(read_block(res))
    out.append("")
    out.append("== 1. AUTO-VERIFIED PASS (reliable exact patterns) ==")
    ok = [cid for cid in AUTO if cid not in failed_ids]
    out.extend(wrap_line("  every AUTO check ran on the changed lines: ", " ".join(AUTO)))
    out.extend(wrap_line("  passed: ", " ".join(ok) or "(none)"))
    if meta["style"] != "skipped":
        out.append("  S0 style-lint ratchet: %s" % meta["style"])
    out.append("")
    out.append("== 2. AUTO-FAILED (confirmed violations; fix them; exit code 1) ==")
    if not res["auto"] and meta["style"] != "FAIL":
        out.append("  (empty)")
    if meta["style"] == "FAIL":
        out.append("  FAIL S0  M39 style-lint ratchet: run Tools/style-lint/check.sh and fix the new hit(s)")
    for cid, rel, line, msg, _ in sorted(res["auto"], key=lambda x: (x[1], x[2])):
        fn, mid, rule, pat, title = AUTO[cid]
        out.append("  FAIL %s  %s %s  %s:%d  %s" % (cid, mid, rule, rel, line, msg))
        out.append("       MUST %s: %s" % (mid, must.get(mid, {}).get("text", "")))
        out.append("       fix: Performance/PATTERNS/%s.md" % pat)
    out.append("")
    items = build_manual(res, must, manual)
    out.append("== 3. MANUAL (NOT verified by this script; answer each in block 4) ==")
    order = sorted(items)
    if not order:
        out.append("  (no UI/Core Swift changes detected: nothing to check)")
    for mid in order:
        e, q = items[mid], manual.get(mid, {})
        if not e["triggered"]:
            out.append("  [%s] applies to %s; no heuristic hit. Full rule in block 4." % (
                mid, " and ".join(e["area"]) or "these paths"))
            continue
        out.append("  [%s] %s" % (mid, q.get("Ask", must.get(mid, {}).get("text", ""))))
        out.append("       because: " + "; ".join(e["why"]))
        for hid, verify, at in e["hints"]:
            out.append("       hint %s: %s" % (hid, verify))
            if at:
                out.append("       where: " + where_lines([(rel, line, None) for rel, line in at]))
        out.append("       if no or unsure: " + q.get("If no or unsure", "escalate"))
        out.append("       re-read: " + q.get("Re-read", "MUST.md section B"))
    expected, why_missing = set(), {}
    for rel, tags in res["tags"].items():
        for tag in tags:
            for mid in PATH_ITEMS.get(tag, []):
                if must.get(mid, {}).get("tag") == "MANUAL":
                    expected.add(mid)
                    why_missing.setdefault(mid, set()).add(tag)
    missing = sorted(m for m in expected if m not in items)
    if missing:
        out.append("  NOT SHOWN for this diff: " + "; ".join(
            "%s (relevant to %s)" % (m, "/".join(sorted(why_missing[m]))) for m in missing))
    if res["waived"]:
        out.append("  [WAIVERS] perf-ok comments found; each needs an ESCALATE line in your report:")
        for cid, rel, line, msg, why in res["waived"]:
            out.append("       %s %s:%d  \"%s\"" % (cid, rel, line, why))
    out.append("")
    out.append("== 4. SIGN-OFF (tick every line with one clause, or write ESCALATE: why; then run --signoff <file>) ==")
    out.append("final-check: base=%s auto-failed=%d auto-pass=%d manual=%d waivers=%d" % (
        meta["base"], len(res["auto"]) + (1 if meta["style"] == "FAIL" else 0), len(ok), len(order), len(res["waived"])))
    for mid in order:
        out.append("[ ] %s %s" % (mid, wrap_rule(must.get(mid, {}).get("text", ""))))
    for cid, rel, line, msg, why in res["waived"]:
        out.append("[ ] WAIVER %s %s:%d ESCALATE: %s" % (cid, rel, line, why))
    hot = sorted(rel for rel, t in res["tags"].items() if (t & HOT_TAGS) and "test" not in t)
    if hot:
        out.extend(wrap_line("measure: REQUIRED. Files in this diff against %s on hot paths: " % meta["base"],
                             ", ".join(os.path.basename(h) for h in hot[:8])))
        out.append("  Follow Performance/MEASURE.md, or record `unmeasured, handed to manager` with the argument, bound and test it asks for.")
    else:
        out.append("measure: not required (no hot-path file in this diff against %s); this output is the evidence" % meta["base"])
    bad = len(res["auto"]) + (1 if meta["style"] == "FAIL" else 0)
    if bad:
        out.append("VERDICT: NOT DONE (auto-failed=%d)" % bad)
    elif meta.get("signoff") is not None:
        verdict, reason = verdict_from_signoff(meta["signoff"])
        out.append("VERDICT: %s%s" % (verdict, (" (%s)" % reason) if reason else ""))
    else:
        out.append("VERDICT: NOT DONE (no complete sign-off supplied; tick block 4, save it, then run: final-check.sh %s --signoff <file>)" % meta["base"])
    wrapped = []
    for ln in out:
        if len(ln) <= 118 or not ln.strip():
            wrapped.append(ln)
            continue
        ind = ln[:len(ln) - len(ln.lstrip())]
        tick = re.match(r"\[[ xX]\] (\S+) ", ln.strip())
        cont = ind + (" " * (len(tick.group(1)) + 4) if tick else "  ")
        wrapped.extend(wrap_line(ind, ln.strip(), 118, cont))
    return "\n".join(wrapped), bad


# --------------------------------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------------------------------


def load_dir(root, rel_root):
    files = []
    for dp, _, fn in os.walk(root):
        for n in sorted(fn):
            if n.endswith(".swift"):
                p = os.path.join(dp, n)
                rel = os.path.relpath(p, root)
                files.append(SwiftFile(rel, read(p), all_lines=True))
    return files


def markers(f, key):
    out = set()
    for i, ln in enumerate(f.raw):
        m = re.search(r"//\s*%s:\s*([A-Z0-9 ]+)" % key, ln)
        if m:
            for cid in m.group(1).split():
                out.add((cid, i + 1))
    return out


def header_features(f):
    for ln in f.raw[:6]:
        m = re.search(r"//\s*features:\s*([A-Z0-9 ]*)", ln)
        if m:
            return set(m.group(1).split())
    return set()


def self_test():
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    must, manual = parse_must(), parse_manual()
    # 1. docs consistency
    for mid, e in must.items():
        if e["tag"] == "MANUAL":
            check(mid in manual and manual[mid].get("Ask") and manual[mid].get("If no or unsure") and manual[mid].get("Re-read"), "MANUAL.md lacks a full entry for " + mid)
        else:
            ids = [x for x in e["checks"] if x in AUTO or x == "S0"]
            check(ids, "%s is tagged AUTO but names no check (%s)" % (mid, e["checks"]))
    for cid, (fn, mid, rule, pat, title) in AUTO.items():
        check(must.get(mid, {}).get("tag") == "AUTO" and cid in must.get(mid, {}).get("checks", []), "%s must be listed on an [AUTO] item %s in MUST.md" % (cid, mid))
        check(os.path.exists(os.path.join(PERF, "PATTERNS", pat + ".md")), "missing PATTERNS/%s.md" % pat)
    for hid, tup in list(HEUR.items()):
        check(must.get(tup[1], {}).get("tag") == "MANUAL", "%s maps to %s which is not a [MANUAL] item" % (hid, tup[1]))
    for fid, name, rx, ms, pats in FEATURES:
        for m in ms:
            check(m in must, "feature %s names unknown %s" % (fid, m))
        for p in pats:
            check(os.path.exists(os.path.join(PERF, "PATTERNS", p + ".md")), "missing PATTERNS/%s.md" % p)
    manual_used = set(x[1] for x in HEUR.values()) | {m for f in FEATURES for m in f[3]} | {m for v in PATH_ITEMS.values() for m in v} | {"M40"}
    for mid, e in must.items():
        if e["tag"] == "MANUAL":
            check(mid in manual_used, "[MANUAL] %s is never asked by any feature, path or heuristic" % mid)
    for dp, _, fn in os.walk(PERF):
        for n in fn:
            if n.endswith(".md"):
                p = os.path.join(dp, n)
                for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", read(p)):
                    if target.startswith(("http", "mailto")):
                        continue
                    q = os.path.normpath(os.path.join(dp, target))
                    check(os.path.exists(q), "broken link in %s: %s" % (os.path.relpath(p, PERF), target))
    # 2. fixtures
    seen_auto, seen_hit, seen_feat = set(), set(), set()
    for kind in ("bad", "good"):
        root = os.path.join(HERE, "fixtures", kind)
        files = load_dir(root, root)
        res = analyse(files)
        got_auto, got_hit, got_waived = {}, {}, {}
        for cid, rel, line, msg, w in res["auto"]:
            got_auto.setdefault(rel, set()).add((cid, line))
        for hid, rel, line, msg, w in res["hits"]:
            got_hit.setdefault(rel, set()).add((hid, line))
        for cid, rel, line, msg, w in res["waived"]:
            got_waived.setdefault(rel, set()).add((cid, line))
        for f in files:
            if "test" in path_tags(f.rel):
                continue
            exp_a, exp_h, exp_w = markers(f, "expect"), markers(f, "hit"), markers(f, "waived")
            check(got_auto.get(f.rel, set()) == exp_a, "%s/%s auto: got %s expected %s" % (kind, f.rel, sorted(got_auto.get(f.rel, set())), sorted(exp_a)))
            check(got_hit.get(f.rel, set()) == exp_h, "%s/%s hits: got %s expected %s" % (kind, f.rel, sorted(got_hit.get(f.rel, set())), sorted(exp_h)))
            check({(c, l) for c, l in got_waived.get(f.rel, set())} == exp_w, "%s/%s waived: got %s expected %s" % (kind, f.rel, sorted(got_waived.get(f.rel, set())), sorted(exp_w)))
            hf = header_features(f)
            check(res["features"].get(f.rel, set()) == hf, "%s/%s features: got %s expected %s" % (kind, f.rel, sorted(res["features"].get(f.rel, set())), sorted(hf)))
            seen_feat |= hf
            if kind == "good":
                check(not exp_a and not exp_h, "good fixture %s carries expect/hit markers" % f.rel)
            else:
                seen_auto |= {c for c, _ in exp_a}
                seen_hit |= {c for c, _ in exp_h}
        if kind == "good":
            check(not res["auto"], "good fixtures produced AUTO failures: %s" % res["auto"][:3])
            check(not res["hits"], "good fixtures produced MANUAL hits: %s" % res["hits"][:3])
            check(res["waived"], "good fixtures contain no perf-ok waiver example")
        # semantic-only items must be MANUAL, never AUTO
        items = build_manual(res, must, manual)
        for mid in items:
            check(must[mid]["tag"] == "MANUAL", "MANUAL block would contain AUTO item " + mid)
    for cid in AUTO:
        check(cid in seen_auto, "no bad fixture proves %s fires" % cid)
    for hid in list(HEUR) + list(SET_LEVEL_HEUR):
        check(hid in seen_hit, "no bad fixture proves %s is reported as MANUAL" % hid)
    for fid, *_ in FEATURES:
        check(fid in seen_feat, "no fixture proves feature %s is detected" % fid)
    # 3. the renderer always has the blocks in order, and its output is answerable
    txt, _ = render({"auto": [], "hits": [], "waived": [], "features": {}, "tags": {}}, must, manual, {"base": "x", "mode": "t", "style": "skipped"})
    pos = [txt.find(k) for k in ("== 0. READ", "== 1. AUTO-VERIFIED PASS", "== 2. AUTO-FAILED", "== 3. MANUAL", "== 4. SIGN-OFF")]
    check(pos == sorted(pos) and -1 not in pos, "output blocks missing or out of order")
    # a stream-tagged diff asks M18 even with no feature and no hit (nothing disappears silently)
    res = {"auto": [], "hits": [], "waived": [], "features": {"a.swift": set()}, "tags": {"a.swift": {"ui", "stream"}}}
    txt, _ = render(res, must, manual, {"base": "x", "mode": "t", "style": "skipped"})
    check("[M18]" in txt, "a stream path does not ask M18")
    sig = txt[txt.find("== 4. SIGN-OFF"):]
    check("".join(sig.split()).find("".join(must["M18"]["text"].split())) >= 0, "the sign-off truncates or rewords M18")
    check(all(len(ln) <= 120 for ln in txt.split("\n")), "an output line is longer than 120 characters")
    # every MANUAL item a path tag can ask is shown for that path (or named as NOT SHOWN)
    for tag, mids in PATH_ITEMS.items():
        res = {"auto": [], "hits": [], "waived": [], "features": {"a.swift": set()}, "tags": {"a.swift": {tag}}}
        txt, _ = render(res, must, manual, {"base": "x", "mode": "t", "style": "skipped"})
        for mid in mids:
            if must.get(mid, {}).get("tag") != "MANUAL":
                continue
            check(re.search(r"\[%s\]|\[ \] %s " % (mid, mid), txt) is not None or "NOT SHOWN" in txt and mid in txt,
                  "path tag %s asks %s but the output neither shows it nor names it NOT SHOWN" % (tag, mid))
    # grouping: more than three locations collapse to "+N more"
    many = {"auto": [], "waived": [], "features": {"a.swift": set()}, "tags": {"a.swift": {"ui", "stream"}},
            "hits": [("H29", "a.swift", n + 10, "scan", None) for n in range(5)]}
    txt, _ = render(many, must, manual, {"base": "x", "mode": "t", "style": "skipped"})
    check("(+2 more)" in txt, "five locations do not collapse to three + '+2 more'")
    # 4. verdict strings
    for text, want in (
            ("[x] M18 reason\n[x] M25 reason", "DONE"),
            ("[x] M18 reason\n[x] M25 reason\nESCALATE: M40 unmeasured", "DONE WITH ESCALATIONS"),
            ("[x] M18 reason\n[ ] M25 reason", "NOT DONE"),
            ("", "NOT DONE"),
            ("[ ] WAIVER C01 a.swift:3 ESCALATE: one-shot", "DONE WITH ESCALATIONS"),
            ("[x] M18 unmeasured, handed to manager: 2 lookups / test", "DONE")):
        got, _ = verdict_from_signoff(text)
        check(got == want, "verdict for %r: got %s want %s" % (text, got, want))
    # every heuristic states what to verify, in a sentence
    for hid, tup in HEUR.items():
        check(len(tup) == 3 and len(tup[2]) > 40 and " " in tup[2], "%s has no verify sentence" % hid)
    # 5. sync_check removal guard: AUTO ids are unique and mapped to AUTO MUST items
    for cid in AUTO:
        check(sum(1 for v in AUTO.values() if v[0].__name__ == AUTO[cid][0].__name__) == 1, "duplicate check function for " + cid)
    if fails:
        print("SELF-TEST FAILED (%d):" % len(fails))
        for x in fails:
            print("  - " + x)
        return 1
    print("SELF-TEST PASSED: %d AUTO checks, %d MANUAL heuristics, %d features, %d MUST items (%d AUTO / %d MANUAL); every check fires on bad fixtures and is silent on good ones" % (
        len(AUTO), len(HEUR) + len(SET_LEVEL_HEUR), len(FEATURES), len(must), sum(1 for e in must.values() if e["tag"] == "AUTO"), sum(1 for e in must.values() if e["tag"] == "MANUAL")))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base", nargs="?")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--style", default="skipped", help="PASS|FAIL|skipped (set by final-check.sh)")
    ap.add_argument("--files", nargs="*", help="check these files in full instead of the git diff")
    ap.add_argument("--read", action="store_true", help="print only the read-first list for this diff")
    ap.add_argument("--signoff", metavar="FILE", help="parse a ticked SIGN-OFF block and print the verdict")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    must, manual = parse_must(), parse_manual()
    signoff = None
    if a.signoff:
        if not os.path.exists(a.signoff):
            print("final-check: no sign-off file at %s" % a.signoff)
            return 2
        signoff = read(a.signoff)
    if a.files:
        files = [SwiftFile(os.path.relpath(os.path.abspath(p), REPO), read(p), all_lines=True) for p in a.files]
        meta = {"base": "(explicit files)", "mode": "whole files", "style": a.style, "source": "given on the command line", "signoff": signoff}
    else:
        ref, mb, info = changed_from_git(a.base)
        if not mb:
            print("final-check: no base ref found (tried the branch upstream, origin/main, main, origin/foundation, foundation); pass one: final-check.sh <base-ref>")
            return 2
        files = []
        for n, lines in info["files"].items():
            files.append(SwiftFile(n, read(os.path.join(REPO, n)), changed=lines, all_lines=lines is None))
        for t in info["tests"]:
            files.append(SwiftFile(t, read(os.path.join(REPO, t)), all_lines=False))
        meta = {"base": "%s merge-base %s" % (ref, mb[:7]), "mode": "changed lines only", "style": a.style,
                "source": info["source"], "signoff": signoff, "empty": mb == git("rev-parse", "HEAD").strip()}
    res = analyse(files)
    if a.read:
        print("\n".join(read_block(res)))
        return 0
    txt, bad = render(res, must, manual, meta)
    print(txt)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
