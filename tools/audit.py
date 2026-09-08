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
    # A zone is DRAWN as soon as render code names it - directly in ZAdd, or as
    # an argument to a helper that calls ZAdd (Toggle, LimRow, KV, Stepper...).
    # Counting only the literals inside ZAdd() hid three toggles that were drawn
    # and never dispatched, while the gate reported '119/119 handled'.
    render = shell[:shell.index('bool OnClick(')]           # everything before the dispatcher
    render = re.sub(r'//[^\n]*', '', render)
    drawn = set(re.findall(r'\b(RZ_[A-Z0-9_]+)\b', render)) - {'RZ_NONE'}
    for m in re.finditer(r'\b(RZ_\w+)\s*\+\s*(\w+)', render):   # RZ_X0 + i : a family
        base = m.group(1)
        if base not in zidx:
            continue
        span = 8 if ('FLT' in base or 'POS' in base) else 12
        for k in range(span):
            if zidx[base] + k < len(zids):
                drawn.add(zids[zidx[base] + k])
    drawn &= set(zids)
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

    # 4b. les DEUX autres plafonds silencieux, jamais mesures jusqu ici.
    #     Le manuel est SATURE (10 sujets pour 10 fentes) : le prochain serait
    #     jete avec un Print que personne ne lit. Et ZAdd jette au-dela de 96
    #     zones sans un mot - c est le defaut de la v3.07, en plus discret.
    hm = re.search(r"#define RCS_HELP_TOPICS (\d+)", shell)
    hr = re.search(r"#define RCS_HELP_ROWS\s+(\d+)", shell)
    # le motif lisait la DECLARATION ; la v3.50 y a mis une constante nommee et
    # le controle a rendu "introuvable" - honnete, mais pas un verdict.
    zm = re.search(r"#define RCS_Z_MAX\s+(\d+)", shell)
    if hm and hr:
        tmax_h = int(hm.group(1))
        rmax_h = int(hr.group(1))
        used_t = len(set(re.findall(r"SetHelpTopic\((\d+),", host)))
        rows = [(int(a), int(b)) for a, b in re.findall(r"SetHelpRow\((\d+),\s*(\d+),", host)]
        used_r = max([b for _, b in rows], default=-1) + 1
        ok_h = (used_t < tmax_h and used_r < rmax_h)
        report("plafond du manuel", ok_h,
               "%d/%d sujets, %d/%d lignes%s" % (used_t, tmax_h, used_r, rmax_h,
                                                 "" if ok_h else "  - SATURE, releve le plafond"))
    else:
        report("plafond du manuel", None, "plafonds du manuel introuvables")
    if zm:
        zcap = int(zm.group(1))
        report("plafond des zones cliquables", len(zids) < zcap,
               "%d zones declarees / %d fentes a l ecran" % (len(zids), zcap))
    else:
        report("plafond des zones cliquables", None, "tableau de zones introuvable")

    # 4c. le defaut n1 de la v3.17 : la section AIDE affichait une version que
    #     le binaire n avait pas, donc un test portait sur le mauvais binaire.
    #     Rien ne reliait les deux chaines. Maintenant si.
    vp = re.search(r'#property version "([\d.]+)"', host)
    vd = re.search(r'#define RC_VERSION_STR "([\d.]+)"', host)
    if vp and vd:
        report("version affichee = version compilee", vp.group(1) == vd.group(1),
               "#property %s / RC_VERSION_STR %s" % (vp.group(1), vd.group(1)))
    else:
        report("version affichee = version compilee", None, "une des deux chaines manque")

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

    # 7. every AddTr carries three non-empty languages.
    #    Le motif n analyse que les entrees a quatre litteraux : celles qu il ne
    #    sait pas lire n etaient ni comptees ni verifiees, et le controle rendait
    #    OK en annoncant un nombre qui se lit comme une couverture complete -
    #    la meme faute que le scan binaire d avant la v3.41. On compare donc les
    #    entrees ANALYSEES aux entrees PRESENTES.
    parsed = list(re.finditer(
        r'AddTr\("(\w+)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\s*\)', hcode))
    # un APPEL commence par un litteral ; sans le guillemet on compte aussi la
    # DEFINITION de la fonction, qui n est pas une entree de traduction.
    total_addtr = len(re.findall(r'\bAddTr\s*\(\s*"', hcode))
    empty = [m.group(1) for m in parsed
             if not (m.group(2) and m.group(3) and m.group(4))]
    if len(parsed) != total_addtr:
        empty.append("%d entrees NON ANALYSEES sur %d" % (total_addtr - len(parsed), total_addtr))
    report("3 langues par entree", not empty, "%d entrees%s" % (
        len(defined), "" if not empty else " | vides : " + " ".join(empty)))

    # 8. an input nobody reads is a bug from the user's seat
    code = hcode
    dead_in = [m.group(1) for m in re.finditer(r'^\s*(?:input|sinput)\s+\w+\s+(\w+)\s*=', hcode, re.M)
               if len(re.findall(r'\b' + m.group(1) + r'\b', code)) <= 1]
    report("reglages actifs", not dead_in, "" if not dead_in else "morts : " + " ".join(dead_in))

    # 8a. Les series d infobulles poussees PAR INDICE sur une plage contigue.
    #     Inserer un id au milieu de la plage decale toute la serie en silence :
    #     chaque texte tombe sur le controle suivant et rien ne se plaint. C est
    #     arrive en v3.27 avec le bouton CADR - le texte de l horloge est tombe
    #     sur lui, et "Retirer : retire RiskCockpit de ce graphique" sur
    #     l horloge, le libelle le plus dangereux pose sur le mauvais controle.
    SERIES = [("tipn_", "RZ_NAV_LOGO", "RZ_NAV_KILL", "barre du haut"),
              ("tipr_", "RZ_RAIL_LIM", "RZ_RAIL_HELP", "rail")]
    zorder = re.findall(r'\b(RZ_\w+)\b',
                        re.search(r'enum ERCZone \{(.*?)\};', shell, re.S).group(1))
    serie_bad = []
    for pfx, first, last, quoi in SERIES:
        if first not in zorder or last not in zorder:
            serie_bad.append("%s : bornes introuvables" % quoi)
            continue
        span = zorder.index(last) - zorder.index(first) + 1
        keys = len(set(re.findall(r'AddTr\("' + pfx + r'(\d+)"', host)))
        if keys != span:
            serie_bad.append("%s : %d cles %s pour %d ids" % (quoi, keys, pfx, span))
    report("series d infobulles alignees", not serie_bad,
           ("%d series" % len(SERIES)) if not serie_bad else " | ".join(serie_bad))

    # 8b. A CACHED SNAPSHOT IS A CONTRACT. The news block computes its fields
    #     once and serves them from s_newsCache for 15 s. Every field the fresh
    #     branch fills must be readable OUT of the cache and writable INTO it.
    #     Miss one and nothing complains : the field exists, it compiles, and the
    #     value is wrong on every frame served from the cache. That is how
    #     newsApplies came to flip twice a second between "there is a news rule"
    #     and "there is none", re-laying out the whole panel with it.
    blk = ""
    m0 = re.search(r"static RCDeckData s_newsCache;", host)
    m1 = re.search(r"end of the 15 s news cache", host)
    if m0 and m1 and m1.start() > m0.start():
        blk = host[m0.start():m1.start()]
    if not blk:
        report("instantane news complet", None, "bloc de cache news introuvable")
    else:
        rd = set(re.findall(r"d\.(news\w+)\s*=\s*s_newsCache\.", blk))
        wr = set(re.findall(r"s_newsCache\.(news\w+)\s*=\s*d\.", blk))
        # what the FRESH branch assigns : d.newsX = <anything that is not the cache>
        fresh = set()
        for f, rhs in re.findall(r"d\.(news\w+)\s*=\s*([^;\n]*)", blk):
            if "s_newsCache" in rhs:
                continue
            fresh.add(f)
        # array element writes (d.newsWhen[i] = ...) carry the base name already
        missing = sorted((fresh - rd) | (fresh - wr))
        report("instantane news complet", not missing,
               ("%d champs, lus et ecrits" % len(fresh)) if not missing
               else "absents du cache : " + " ".join(missing))

    # 8c. UN GARDE-FOU DOIT GARDER QUELQUE CHOSE. Une temporisation peut etre
    #     declaree, commentee, remise a zero a chaque attache - et ne proteger
    #     rien du tout : le compilateur voit une variable ECRITE, donc utilisee.
    #     `g_last_telegram_alert[]` a porte « prevents spam on flapping
    #     transitions » pendant vingt-neuf versions sans jamais etre comparee a
    #     une horloge, et le son qu elle devait proteger a tourne a 2 Hz.
    #     Ici : tout nom de temporisation doit apparaitre dans une COMPARAISON.
    guard_names = set(re.findall(r'#define\s+(RC_\w*(?:COOLDOWN|THROTTLE)\w*)', hcode))
    guard_names |= set(re.findall(r'\bdatetime\s+(g_\w*(?:alert|throttle|cooldown)\w*)\s*[\[=;]',
                                  hcode, re.I))
    guard_dead = []
    for g in sorted(guard_names):
        cmp_hit = [ln for ln in hcode.split("\n")
                   if re.search(r'\b' + g + r'\b', ln) and re.search(r'[<>]=?', ln)]
        if not cmp_hit:
            guard_dead.append(g)
    report("garde-fous branches", not guard_dead,
           ("%d temporisations comparees" % len(guard_names)) if not guard_dead
           else "jamais comparees : " + " ".join(guard_dead))

    # 9. PUBLIC repo : nothing personal, in the sources or in the binary.
    #    The binary check needs its positive control first.
    # One or TWO backslashes : source code escapes them, markdown and comments
    # do not. The old pattern demanded two and therefore matched nothing.
    # A USER path leaks ; C:\Program Files is standard build documentation.
    # un chemin local s ecrit avec des antislashs OU des barres obliques : le
    # motif n en voyait qu une forme, et le meme chemin passait en clair.
    pats = [("chemin local", r"[A-Za-z]:[\\/]{1,2}(?:Users|_Home)"),
            ("dossier terminal", r"Terminal\\{1,2}[0-9A-F]{32}"),
            ("token telegram", r"\d{8,10}:[A-Za-z0-9_-]{30,}"),
            ("email perso", r"(?i)[\w.+-]+@(?:gmail|yahoo|hotmail|outlook)\.[a-z]{2,}"),
            ("login MT5", None)]   # handled below : see NUM_OK
    # A PUBLIC repo : eight to ten consecutive digits ARE an account number
    # until proven otherwise. The old pattern wanted the word compte/login
    # within three characters of the digits - and the leak that actually
    # shipped read "compte **demo** Ava, <number>", fourteen characters away,
    # so this control returned OK on the very file that carried the number.
    # An allowlist forces a CONSCIOUS decision for every new number instead.
    NUM_OK = {
        # FundedNext help-centre article ids, cited as sources in the catalogue
        "8020351", "10256545", "10701447", "10816539", "10816788",
        "11641614", "11982271", "11982604", "12840751",
        "20260509",    # a YYYYMMDD date, RC_Math + its self-test
        "100000000",   # a round guard value, not an identifier
    }
    # 7 a 10 chiffres : un login MT5 de 7 chiffres passait sous le motif 8-10.
    NUM_RX = re.compile(r"(?<![\d.])\d{7,10}(?![\d.])")

    def num_leaks(text, where):
        # an id quoted as a documentation SOURCE is not a leak : the only shape
        # accepted is a URL path, e.g. help.fundednext.com/en/articles/12840751
        out = []
        for m in NUM_RX.finditer(text):
            if m.group(0) in NUM_OK:
                continue
            # cette exemption etait une regle de PROXIMITE de 40 caracteres :
            # elle blanchissait un vrai login des qu une URL d article trainait
            # n importe ou avant lui. Les chiffres doivent SUIVRE "articles/".
            if text[max(0, m.start() - 9):m.start()] == "articles/":
                continue
            out.append("%s:login MT5 (%s)" % (where, m.group(0)))
        return out
    leaks = []
    # every text file, not a hand-picked list : the leak that got through was in
    # HISTORY.md - the changelog that described its own removal.
    # Une liste blanche d EXTENSIONS laissait dehors tout fichier qui n en a
    # pas - LICENSE en tete - pendant que le rapport annoncait un nombre de
    # fichiers scannes, ce qui se lit comme une couverture complete. On lit
    # maintenant TOUT ce qui se decode en texte, et on DIT ce qui a ete ecarte.
    BINAIRE = ('.ex5', '.ex4', '.png', '.ico', '.bmp', '.jpg', '.gif', '.zip', '.wav')
    scanned, ecartes = [], []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d != '.git']
        for f in files:
            rel = os.path.relpath(os.path.join(base, f), root)
            if f.lower().endswith(BINAIRE):
                ecartes.append(rel)
                continue
            scanned.append(rel)
    for rel in scanned:
        txt = read(root, rel)
        if txt is None:
            continue
        for label, rx in pats:
            if rx is None:
                continue
            for m in re.finditer(rx, txt):
                leaks.append("%s:%s" % (os.path.basename(rel), label))
        leaks += num_leaks(txt, os.path.basename(rel))
    # THE SOURCES carry the verdict : they are plain text, every byte is readable,
    # a leak in them cannot hide.
    report("fuite de donnees perso (sources)", not leaks,
           ("%d fichiers texte lus, %d binaires ecartes" % (len(scanned), len(ecartes)))
           if not leaks else " | ".join(sorted(set(leaks))))

    # THE BINARY is a separate, weaker check, and it must say so. Its positive
    # control looks for the #property link string - and #property strings sit
    # UNCOMPRESSED as UTF-16LE in the .ex5 HEADER while body strings are
    # compressed. So the control proves we can read ~0.3 % of the file and
    # nothing about the 99.7 % where a leaked string would actually live. It used
    # to report "12 files + binary scanned" with no leak, which reads as "the
    # binary is clean". That is not a verdict, it is the absence of one.
    ex5 = read(root, EX5, binary=True)
    blk = []
    if ex5 is None:
        report("fuite dans le binaire (en-tete seul)", None, "pas de .ex5 a scanner")
    else:
        control = ex5.find("javadrazavi.fr".encode('utf-16-le')) >= 0
        if not control:
            report("fuite dans le binaire (en-tete seul)", None,
                   "controle positif ECHOUE - aucun verdict possible")
        else:
            for enc in ('latin-1', 'utf-16-le'):
                btxt = ex5.decode(enc, 'ignore')
                for label, rx in pats:
                    if rx is None:
                        continue
                    if re.search(rx, btxt):
                        blk.append("RiskCockpit.ex5:" + label)
                blk += num_leaks(btxt, "RiskCockpit.ex5")
            report("fuite dans le binaire (en-tete seul)", not blk,
                   "en-tete lisible, corps COMPRESSE donc NON couvert" if not blk
                   else " | ".join(sorted(set(blk))))
    if False:
            report("fuite de donnees perso", not leaks,
                   ("%d fichiers + binaire scannes" % len(scanned)) if not leaks
                   else " | ".join(sorted(set(leaks))))

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
        # ce controle ne comparait que DEUX des sources compilees : le catalogue
        # des regles prop, les maths pures et le canevas pouvaient etre plus
        # recents que le binaire sans que rien ne le dise. Toutes, maintenant.
        srcs = [IND]
        libdir = os.path.join(root, 'Libraries')
        if os.path.isdir(libdir):
            for f in sorted(os.listdir(libdir)):
                if f.lower().endswith('.mqh'):
                    srcs.append(os.path.join('Libraries', f))
        stale = [r for r in srcs if mtime(r) > mtime(EX5) + 1]
        report("binaire a jour", not stale,
               ("%d sources comparees" % len(srcs)) if not stale
               else "plus recents que le .ex5 : " + " ".join(stale))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=ROOT, help="repository to audit")
    args = ap.parse_args()
    print("RiskCockpit - audit statique de", args.path)
    run(args.path)
    print("\n".join(results))
    print("\n%d controle(s) sur %d en echec." % (len(FAIL), len(results)))
    sys.exit(1 if FAIL else 0)
