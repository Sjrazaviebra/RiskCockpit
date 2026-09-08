# -*- coding: utf-8 -*-
"""Self-test of tools/audit.py - can the gate actually say NO ?

    python tools/gate_selftest.py

Copies the repository to a temporary directory, injects ONE defect at a time,
and checks the matching line turns FAIL. An audit nobody ever saw fail is a
decoration, not a gate.

The first version of this test reported three "the gate missed it" that were
really injections with no effect - so every injection is now verified to have
changed the file, and a no-op is reported as a BROKEN TEST, never as a miss.
It earned its keep immediately : it found that the gate counted a
commented-out SetLabel as a pushed label.
"""
import io, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IND = os.path.join("Indicators", "RiskCockpit.mq5")
SHELL = os.path.join("Libraries", "RC_ShellUI.mqh")
MATH = os.path.join("Libraries", "RC_Math.mqh")


def mut_bom(b):    return b'\xef\xbb\xbf' + b                      # double BOM
def mut_input(b):  return b.replace(b'input bool ', b'input int InpDeadOne = 3;\r\ninput bool ', 1)
def mut_leak(b):
    # built by concatenation on purpose : this FILE must not itself contain a
    # string shaped like a leak, or the gate would flag its own test harness.
    # the injection deliberately does NOT put the word 'login' next to the
    # digits any more : that is exactly the shape the old pattern missed.
    fake = b'// compte **demo** Ava, ' + b'9911' + b'22337'
    return b.replace(b'#property version', fake + b'\r\n#property version', 1)
def mut_label(b):  return b.replace(b'g_shell.SetLabel(RCL_PAYOUT,', b'//g_shell.SetLabel(RCL_PAYOUT,', 1)
def mut_key(b):    return re.sub(rb'    AddTr\("shl_pyramid",.*?\);\r\n', b'', b, count=1, flags=re.S)
def mut_brace(b):  return b.replace(b'int OnInit(void) {', b'int OnInit(void) { if (true) {', 1)
def mut_path(b):
    # a local path written NORMALLY (one backslash), the form a markdown file or
    # a code comment carries. The old pattern demanded two and matched nothing.
    p = b'// ' + b'C:' + b'\\' + b'Users' + b'\\' + b'someone'
    return b.replace(b'#property version', p + b'\r\n#property version', 1)


def mut_ver(b):    return re.sub(rb'#property version "[\d.]+"',
                                 b'#property version "9.99"', b, count=1)  # source ahead of the binary


def mut_serie(b):
    # Retirer une cle de la serie de la barre du haut : tous les textes suivants
    # tombent sur le controle d a cote, sans un mot du compilateur. C est
    # exactement la regression posee en v3.27 par l insertion du bouton CADR.
    return b.replace(b'AddTr("tipn_9"', b'AddTr("tipn_x9"', 1)


def mut_lmax(b):
    # 187 ids de libelles : un plafond de 32 en jetterait la plupart, chacun
    # avec un Print - et le libelle non pousse retomberait sur son defaut FR.
    return b.replace(b'#define RCS_L_MAX 256', b'#define RCS_L_MAX 32', 1)


def mut_tipmax(b):
    return b.replace(b'#define RCS_TIP_MAX 256', b'#define RCS_TIP_MAX 32', 1)


def mut_lang(b):
    # une entree i18n a deux langues au lieu de trois : l espagnol disparait
    # sans bruit et l utilisateur ES lit de l anglais.
    return b.replace(b'AddTr("shl_navroom", "ROOM", "MARGE", "MARGEN");',
                     b'AddTr("shl_navroom", "ROOM", "MARGE", "");', 1)


def mut_helpcap(b):
    # le manuel a 10 sujets : un plafond de 4 les jetterait, avec un Print que
    # personne ne lit. C est le defaut de la v3.07, en plus discret.
    return b.replace(b'#define RCS_HELP_TOPICS 16', b'#define RCS_HELP_TOPICS 4', 1)


def mut_zcap(b):
    # ZAdd jette au-dela du plafond : une zone jetee est un controle qui ne
    # repond plus au clic, sans erreur et sans trace.
    return b.replace(b'#define RCS_Z_MAX       256', b'#define RCS_Z_MAX       32', 1)


def mut_verstr(b):
    # le defaut n1 de la v3.17 : la version AFFICHEE et la version COMPILEE se
    # separent, et un test porte alors sur un binaire qu on croit etre l autre.
    return re.sub(rb'#define RC_VERSION_STR "[\d.]+"',
                  b'#define RC_VERSION_STR "0.01"', b, count=1)


def mut_touchlib(b):
    # une source incluse plus recente que le .ex5 : le binaire livre ne contient
    # pas ce qu on vient d ecrire. Un commentaire suffit - c est la DATE qui compte.
    return b + b'\r\n// gate_selftest : source plus recente que le binaire\r\n'


def mut_snapshot(b):
    # Drop ONE field from the cached snapshot's write-back. The field still
    # exists, the code still compiles, and its value is simply wrong on every
    # frame served from the cache - which is exactly how newsApplies came to
    # flip twice a second between "there is a news rule" and "there is none".
    return b.replace(b's_newsCache.newsWinMin = d.newsWinMin;', b'', 1)


# (libelle attendu, fichier a muter, mutation)
def mut_guard(b):
    # Debrancher la temporisation du son : la variable reste declaree,
    # commentee et remise a zero a l attache - mais plus rien ne la compare
    # a une horloge. C est l etat exact dans lequel g_last_telegram_alert[]
    # a passe vingt-neuf versions, en promettant de brider un son qu il ne
    # bridait pas. Le compilateur ne voit rien : la variable est ECRITE.
    return b.replace(
        b'    if (TimeCurrent() - g_last_sound_alert[idx] < RC_SOUND_COOLDOWN_SEC)',
        b'    if (false)', 1)


CASES = [
    ("BOM unique", IND, mut_bom),
    ("reglages actifs", IND, mut_input),
    ("fuite de donnees perso", IND, mut_leak),
    ("libelles traduits", IND, mut_label),
    ("cles i18n resolues", IND, mut_key),
    ("accolades equilibrees", IND, mut_brace),
    ("version du binaire", IND, mut_ver),
    ("fuite de donnees perso", IND, mut_path),   # the pattern that had rotted
    ("instantane news complet", IND, mut_snapshot),
    ("plafond du manuel", SHELL, mut_helpcap),
    ("plafond des zones cliquables", SHELL, mut_zcap),
    ("version affichee = version compilee", IND, mut_verstr),
    ("binaire a jour", MATH, mut_touchlib),
    ("plafond des libelles", SHELL, mut_lmax),
    ("plafond des infobulles", SHELL, mut_tipmax),
    ("3 langues par entree", IND, mut_lang),
    ("series d infobulles alignees", IND, mut_serie),
    ("garde-fous branches", IND, mut_guard),
]

# Ce que le harnais NE couvre pas, et pourquoi. Un self-test qui tait sa
# couverture ment de la meme facon qu un controle qui ne peut pas echouer.
NON_COUVERTS = {
    "zones cliquables gerees":
        "toute zone dessinee est deja traitee ; injecter un id orphelin demanderait "
        "d en inventer un, ce qui testerait l injection et pas le controle",
    "fuite dans le binaire (en-tete seul)":
        "il faudrait recompiler avec une fuite dans une chaine du corps - or le "
        "corps est compresse, donc le controle ne pourrait pas la voir : c est "
        "exactement ce que son libelle annonce",
}


def main():
    allgood = True
    for label, target, mutate in CASES:
        tmp = tempfile.mkdtemp(prefix="rcgate_")
        dst = os.path.join(tmp, "repo")
        shutil.copytree(ROOT, dst, ignore=shutil.ignore_patterns('.git'))
        p = os.path.join(dst, target)
        before = io.open(p, 'rb').read()
        after = mutate(before)
        if after == before:
            print("%-26s -> TEST CASSE (injection sans effet)" % label)
            allgood = False
            shutil.rmtree(tmp, ignore_errors=True)
            continue
        io.open(p, 'wb').write(after)
        r = subprocess.run([sys.executable, os.path.join(dst, "tools", "audit.py"), "--path", dst],
                           capture_output=True, text=True)
        hit = [l for l in r.stdout.splitlines() if label in l]
        caught = bool(hit) and hit[0].startswith(("[FAIL]", "[????]"))
        print("%-26s -> %-9s %s" % (label, "DETECTE" if caught else "MANQUE !!",
                                    (hit[0][:76] if hit else "(ligne absente)")))
        allgood &= caught
        shutil.rmtree(tmp, ignore_errors=True)
    couverts = sorted(set(c[0] for c in CASES))
    print("\ncontroles exerces : %d" % len(couverts))
    for k, why in sorted(NON_COUVERTS.items()):
        print("  NON COUVERT  %-38s %s" % (k, why))
    print("\nle gate attrape chaque defaut injecte :", allgood)
    return 0 if allgood else 1


if __name__ == "__main__":
    sys.exit(main())
