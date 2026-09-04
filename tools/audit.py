# -*- coding: utf-8 -*-
"""RiskCockpit - static audit gate.

One command, one verdict. Run it from anywhere :

    python tools/audit.py            # audit the repository
    python tools/audit.py --path X   # audit another checkout

Every check answers a question the MQL5 compiler CANNOT answer, because none
of these failures break a build : a click zone nobody handles, a label that can
never be translated, a setting that no longer does anything, a personal account
number left in a public file.

Each check that inspects a binary or a generated artefact carries a POSITIVE
CONTROL first : if the instrument cannot see a value it is known to contain,
the check reports UNKNOWN instead of "clean". An instrument that cannot say NO
is not a measurement.

Exit code 0 = every check passed, 1 = at least one failed or is unknown.
"""
import io, os, re, sys, argparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IND = os.path.join("Indicators", "RiskCockpit.mq5")
EX5 = os.path.join("Indicators", "RiskCockpit.ex5")
SHELL = os.path.join("Libraries", "RC_ShellUI.mqh")

FAIL, results = [], []


def report(name, ok, detail=""):
    tag = "OK  " if ok is True else ("FAIL" if ok is False else "????")
    results.append("[%s] %-34s %s" % (tag, name, detail))
    if ok is not True:
        FAIL.append(name)


def read(root, rel, binary=False):
    p = os.path.join(root, rel)
    if not os.path.exists(p):
        return None
    b = io.open(p, 'rb').read()
    return b if binary else b.decode('utf-8-sig')


def code_only(line):
    """the line with string / char literals and // comments blanked out"""
    out, i, n = [], 0, len(line)
    while i < n:
        ch = line[i]
        if ch == '/' and i + 1 < n and line[i + 1] == '/':
            break
        if ch in '"\'':
            q = ch
            i += 1
            while i < n and line[i] != q:
                if line[i] == '\\':
                    i += 1
                i += 1
            i += 1
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def expr_after(text, start):
    """the balanced ( ... ) expression that starts at `start` (just past '(')"""
    i, depth = start, 1
    while i < len(text) and depth:
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
        i += 1
    return text[start:i - 1]


# --------------------------------------------------------------- checks ----
def check_encoding(host):
    raw = host.encode('utf-8')
    nb = 0  # the decoded string no longer carries the BOM ; re-read raw instead
    return nb


def run(root):
    host = read(root, IND)
    shell = read(root, SHELL)
    if host is None or shell is None:
        report("fichiers presents", False, "source introuvable sous " + root)
        return
    raw = read(root, IND, binary=True)

    # 1. exactly one UTF-8 BOM : without it MetaEditor reads the file as ANSI
    #    and every accent becomes mojibake (this happened, v2.14.06).
    n_bom = (len(raw) - len(raw.lstrip(b'\xef\xbb\xbf'))) // 3
    report("BOM unique sur le .mq5", n_bom == 1, "trouve : %d" % n_bom)

    # 2. braces balance on CODE only (strings and comments lie)
    depth = 0
    for line in host.split('\n'):
        c = code_only(line)
        depth += c.count('{') - c.count('}')
    report("accolades equilibrees", depth == 0, "solde : %+d" % depth)

    # 3. every drawn click zone is handled in OnClick
    zenum = re.search(r'enum ERCZone \{(.*?)\};', shell, re.S).group(1)
    zids = re.findall(r'\b(RZ_\w+)\b', zenum)
    zidx = {n: i for i, n in enumerate(zids)}
    drawn = set()
    for m in re.finditer(r'ZAdd\([^;]*?\b(RZ_\w+)\b\s*(\+\s*\w+)?\s*\)', shell, re.S):
        base, off = m.group(1), m.group(2)
        if not off:
            drawn.add(base)
        else:
            span = 8 if ('FLT' in base or 'POS' in base) else 12
            for k in range(span):
                if zidx[base] + k < len(zids):
                    drawn.add(zids[zidx[base] + k])
    body = shell[shell.index('bool OnClick('):]
    handled = set(re.findall(r'case\s+(RZ_\w+)\s*:', body))
    handled |= set(re.findall(r'hit\s*==\s*(RZ_\w+)', body))
    for a, b in re.findall(r'hit\s*>=\s*(RZ_\w+)\s*&&\s*hit\s*<=\s*(RZ_\w+)', body):
        for k in range(zidx[a], zidx[b] + 1):
            handled.add(zids[k])
    orphans = sorted(drawn - handled - {'RZ_NONE'}, key=lambda z: zidx[z])
    report("zones cliquables gerees", not orphans,
           "%d/%d dessinees%s" % (len(drawn & handled), len(drawn),
                                  "" if not orphans else " | orphelines : " + " ".join(orphans)))

    # 4. the two silent caps : an id past the array is dropped without a word
    lmax = int(re.search(r'#define RCS_L_MAX (\d+)', shell).group(1))
    tmax = int(re.search(r'#define RCS_TIP_MAX (\d+)', shell).group(1))
    lids = re.findall(r'\b(RCL_\w+)\b',
                      re.search(r'enum ERCLabel \{(.*?)\};', shell, re.S).group(1))
    report("plafond des libelles", len(lids) <= lmax, "%d ids / %d slots" % (len(lids), lmax))
    report("plafond des infobulles", len(zids) <= tmax, "%d zones / %d slots" % (len(zids), tmax))

    # comment-free views : a commented-out SetLabel used to count as pushed
    # (the gate's own blind spot, found by tools/gate_selftest.py). The leak
    # scan below deliberately KEEPS comments - a leak in a comment is a leak.
    hcode = re.sub(r'//[^\n]*', '', host)
    scode = re.sub(r'//[^\n]*', '', shell)

    # 5. every label the shell can ASK for is pushed by the host.
    #    Walk the whole L( ... ) expression : a ternary hides ids from a regex.
    asked = set()
    for m in re.finditer(r'\bL\(', scode):
        asked |= set(re.findall(r'\b(RCL_\w+)\b', expr_after(scode, m.end())))
    pushed = set(re.findall(r'SetLabel\((RCL_\w+),', hcode))
    miss = sorted(asked - pushed)
    report("libelles traduits", not miss, "%d demandes, %d pousses%s" % (
        len(asked), len(pushed), "" if not miss else " | manquants : " + " ".join(miss)))

    # 6. every i18n key the code can ask for still exists in the table
    defined = set(re.findall(r'AddTr\("(\w+)"', hcode))
    prefixes = set(re.findall(r'Tr\("(\w+_)"\s*\+', hcode))
    missing = set()
    for m in re.finditer(r'\bTr\(', hcode):
        for lit in re.findall(r'"([^"]*)"', expr_after(hcode, m.end())):
            if lit and re.fullmatch(r'\w+', lit) and lit not in defined:
                if not any(lit.startswith(p) for p in prefixes):
                    missing.add(lit)
    report("cles i18n resolues", not missing,
           "%d cles definies%s" % (len(defined),
                                   "" if not missing else " | introuvables : " + " ".join(sorted(missing))))

    # 7. every AddTr carries three non-empty languages
    empty = [m.group(1) for m in re.finditer(
        r'AddTr\("(\w+)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\s*\)', hcode)
        if not (m.group(2) and m.group(3) and m.group(4))]
    report("3 langues par entree", not empty, "%d entrees%s" % (
        len(defined), "" if not empty else " | vides : " + " ".join(empty)))

    # 8. an input nobody reads is a bug from the user's seat
    code = hcode
    dead_in = [m.group(1) for m in re.finditer(r'^\s*(?:input|sinput)\s+\w+\s+(\w+)\s*=', hcode, re.M)
               if len(re.findall(r'\b' + m.group(1) + r'\b', code)) <= 1]
    report("reglages actifs", not dead_in, "" if not dead_in else "morts : " + " ".join(dead_in))

    # 9. PUBLIC repo : nothing personal, in the sources or in the binary.
    #    The binary check needs its positive control first.
    pats = [("chemin local", r"C:\\\\Users\\\\|F:\\\\_Home"),
            ("token telegram", r"\d{8,10}:[A-Za-z0-9_-]{30,}"),
            ("email perso", r"(?i)[\w.+-]+@(?:gmail|yahoo|hotmail|outlook)\.[a-z]{2,}"),
            ("login MT5", r"(?i)\blogin\s*:?\s*\d{6,10}\b|\bcompte\s+\d{7,10}\b")]
    leaks = []
    for rel in (IND, SHELL, os.path.join("Libraries", "CChallengeProfileCatalog.mqh"),
                os.path.join("Services", "RCNewsFeeder.mq5"), "README.md"):
        txt = read(root, rel)
        if txt is None:
            continue
        for label, rx in pats:
            for m in re.finditer(rx, txt):
                leaks.append("%s:%s" % (os.path.basename(rel), label))
    ex5 = read(root, EX5, binary=True)
    if ex5 is None:
        report("fuite de donnees perso", None, "pas de .ex5 a scanner")
    else:
        control = ex5.find("javadrazavi.fr".encode('utf-16-le')) >= 0
        if not control:
            report("fuite de donnees perso", None,
                   "controle positif du scan binaire ECHOUE - aucun verdict possible")
        else:
            for enc in ('latin-1', 'utf-16-le'):
                txt = ex5.decode(enc, 'ignore')
                for label, rx in pats:
                    if re.search(rx, txt):
                        leaks.append("RiskCockpit.ex5:" + label)
            report("fuite de donnees perso", not leaks,
                   "sources + binaire scannes" if not leaks else " | ".join(sorted(set(leaks))))

    # 10. the binary must CLAIM the same version as the source. Dates alone let
    #     a v2.02.03 binary sit next to a v3 source for two months : both files
    #     looked plausible, and nothing said otherwise.
    ver_src = re.search(r'#property version "([\d.]+)"', host)
    if ex5 is None or ver_src is None:
        report("version du binaire", None, "pas de .ex5 ou pas de #property version")
    else:
        control = ex5.find("javadrazavi.fr".encode('utf-16-le')) >= 0
        found = ex5.find(ver_src.group(1).encode('utf-16-le')) >= 0
        if not control:
            report("version du binaire", None, "en-tete illisible - aucun verdict")
        else:
            report("version du binaire", found,
                   "source %s %s le binaire" % (ver_src.group(1),
                                                "presente dans" if found else "ABSENTE de"))

    # 10. the shipped binary must not be older than the sources it claims to be
    def mtime(rel):
        p = os.path.join(root, rel)
        return os.path.getmtime(p) if os.path.exists(p) else 0
    if ex5 is not None:
        stale = [r for r in (IND, SHELL) if mtime(r) > mtime(EX5) + 1]
        report("binaire a jour", not stale,
               "" if not stale else "plus recents que le .ex5 : " + " ".join(stale))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=ROOT, help="repository to audit")
    args = ap.parse_args()
    print("RiskCockpit - audit statique de", args.path)
    run(args.path)
    print("\n".join(results))
    print("\n%d controle(s) sur %d en echec." % (len(FAIL), len(results)))
    sys.exit(1 if FAIL else 0)
