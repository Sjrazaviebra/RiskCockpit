# -*- coding: utf-8 -*-
"""
prep_screens.py — met les captures d'ecran aux specifications du MQL5 Market.

USAGE : deposer les captures brutes (PNG/JPG) dans market/screens/, puis :
            python prep_screens.py

CE QU'IL FAIT, SUR PLACE :
  - refuse une image dont le plus petit cote est < 720 px APRES traitement
    (la regle du Market : minimum 720 px sur UN cote) ;
  - reduit a 1920x1080 maximum en gardant les proportions ;
  - recompresse tant que le fichier depasse 2 Mo ;
  - REFUSE et le DIT si une image ne peut pas satisfaire les regles, au lieu de
    produire un fichier qui sera rejete a la soumission.

⚠️ CE QU'IL NE PEUT PAS VERIFIER : que le texte de la capture soit en ANGLAIS.
   C'est a l'oeil. Le piege connu : les scripts « SB_* » sont les copies internes
   et restent en FRANCAIS ; les copies publiques s'appellent ForgeExport /
   ForgeParity / HorizonProbe, SANS prefixe. Une capture prise sur le mauvais
   script passe toutes les verifications techniques et se fait refuser a la
   validation.
"""
import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from PIL import Image

DOSSIER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "market", "screens")
COTE_MIN = 720          # regle Market : au moins 720 px sur un cote
MAX_L, MAX_H = 1920, 1080
POIDS_MAX = 2 * 1024 * 1024
EXT = (".png", ".jpg", ".jpeg", ".gif")


def traite(chemin: str) -> str:
    im = Image.open(chemin)
    l0, h0 = im.size

    # 1. Reduction si l'image depasse le cadre autorise, proportions gardees.
    if l0 > MAX_L or h0 > MAX_H:
        f = min(MAX_L / l0, MAX_H / h0)
        im = im.resize((max(1, int(l0 * f)), max(1, int(h0 * f))), Image.LANCZOS)

    l, h = im.size
    # 2. La regle demande >= 720 px sur UN cote, pas sur les deux.
    if max(l, h) < COTE_MIN:
        return "⛔ REFUSE : %dx%d — aucun cote n'atteint %d px, et agrandir une capture la rend illisible" % (l, h, COTE_MIN)

    # 3. Poids. On recompresse, en PNG d'abord (sans perte), puis en JPEG si besoin.
    base, _ = os.path.splitext(chemin)
    sortie = base + ".png"
    im.convert("RGB").save(sortie, "PNG", optimize=True)
    if os.path.getsize(sortie) > POIDS_MAX:
        os.remove(sortie)
        sortie = base + ".jpg"
        for q in (92, 85, 78, 70, 60):
            im.convert("RGB").save(sortie, "JPEG", quality=q, optimize=True)
            if os.path.getsize(sortie) <= POIDS_MAX:
                break
        else:
            return "⛔ REFUSE : encore au-dessus de 2 Mo apres recompression"
    if sortie != chemin and os.path.exists(chemin):
        os.remove(chemin)
    return "✅ %-34s %4dx%-4d  %6.0f Ko" % (os.path.basename(sortie), l, h, os.path.getsize(sortie) / 1024)


def main() -> int:
    if not os.path.isdir(DOSSIER):
        os.makedirs(DOSSIER)
        print("Dossier cree : market/screens/ — y deposer les captures, puis relancer.")
        return 0

    fichiers = [f for f in sorted(os.listdir(DOSSIER)) if f.lower().endswith(EXT)]
    if not fichiers:
        print("market/screens/ est vide. Y deposer les captures, puis relancer.")
        return 0
    if len(fichiers) > 12:
        print("⚠️ %d captures : le Market en accepte 12 au maximum." % len(fichiers))

    for f in fichiers:
        print("  " + traite(os.path.join(DOSSIER, f)))
    print("\n⚠️ Verification qui reste A L'OEIL : le texte doit etre en ANGLAIS.")
    print("   Les scripts « SB_* » sont les copies internes et sont en FRANCAIS.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
