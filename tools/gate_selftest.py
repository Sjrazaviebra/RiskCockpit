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


def mut_bom(b):    return b'\xef\xbb\xbf' + b                      # double BOM
def mut_input(b):  return b.replace(b'input bool ', b'input int InpDeadOne = 3;\r\ninput bool ', 1)
def mut_leak(b):
    # built by concatenation on purpose : this FILE must not itself contain a
    # string shaped like a leak, or the gate would flag its own test harness.
    fake = b'// log' + b'in ' + b'12345678'
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


CASES = [
    ("BOM unique", mut_bom),
    ("reglages actifs", mut_input),
    ("fuite de donnees perso", mut_leak),
    ("libelles traduits", mut_label),
    ("cles i18n resolues", mut_key),
    ("accolades equilibrees", mut_brace),
    ("version du binaire", mut_ver),
    ("fuite de donnees perso", mut_path),   # the pattern that had rotted
]


def main():
    allgood = True
    for label, mutate in CASES:
        tmp = tempfile.mkdtemp(prefix="rcgate_")
        dst = os.path.join(tmp, "repo")
        shutil.copytree(ROOT, dst, ignore=shutil.ignore_patterns('.git'))
        p = os.path.join(dst, IND)
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
    print("\nle gate attrape chaque defaut injecte :", allgood)
    return 0 if allgood else 1


if __name__ == "__main__":
    sys.exit(main())
