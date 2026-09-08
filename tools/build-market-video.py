# -*- coding: utf-8 -*-
u"""Vidéo produit RiskCockpit pour la fiche MQL5 Market (lien YouTube non répertorié).

⛔ AUCUN pilotage de MT5 : ce script n'assemble que des captures DÉJÀ prises et vérifiées. La
séance de captures est décrite dans market/screens/SHOTLIST.md et se fait à part.

🎨 Palette et police ÉCHANTILLONNÉES SUR LE PRODUIT (pas choisies) : fond du thème EMER D
(7,20,16), surface (16,36,28), accent (45,212,191), texte (236,253,245), estompé (107,155,138),
Segoe UI. La vidéo doit se lire comme le panneau, pas comme une couche marketing posée dessus.

⚖️ Règles Part IV appliquées à chaque texte : aucune promesse ni suggestion de gain, aucun
superlatif, aucun backtest, aucun lien externe. Chaque phrase dit ce que l'outil MESURE ou ce
qu'il REFUSE de faire.

🔇 La piste audio est SYNTHÉTISÉE par tools/build-market-music.py : ni revendication Content ID
possible, ni attribution à porter. ffmpeg est localisé à l'exécution, jamais écrit en dur.

📺 QUALITÉ (v2) : la première chaîne passait par un intermédiaire MPEG-4 à ~3 Mb/s écrit par
OpenCV, puis recollait le son — donc DEUX encodages, dont un dans un codec des années 2000, sur
des captures d'interface pleines de texte fin. Les images vont maintenant directement dans
ffmpeg par un tube, en RAW : il n'y a plus qu'UN seul encodage, en H.264 à 12 Mb/s, le format
que YouTube réencode le mieux. Sur du texte, la différence se voit.
"""
import os
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'market', 'screens')
VID = os.path.join(ROOT, 'market', 'video')
WAV = os.path.join(VID, 'RiskCockpit-track.wav')
OUT = os.path.join(VID, 'RiskCockpit-overview.mp4')


def find_ffmpeg():
    """ffmpeg, sans ecrire un chemin personnel dans un depot PUBLIC.

    On regarde le PATH d abord, puis les emplacements ou un ffmpeg se trouve
    deja sur une machine Windows ordinaire - CapCut en embarque un. Le chemin
    est CONSTRUIT a l execution depuis les variables d environnement : il n y a
    donc aucun nom d utilisateur ecrit dans ce fichier.
    """
    from shutil import which
    p = which('ffmpeg')
    if p:
        return p
    base = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'CapCut', 'Apps')
    if os.path.isdir(base):
        for d in sorted(os.listdir(base), reverse=True):
            c = os.path.join(base, d, 'ffmpeg.exe')
            if os.path.exists(c):
                return c
    return ''


FFMPEG = find_ffmpeg()

W, H, FPS = 1920, 1080, 25

BG = (7, 20, 16)            # thème EMER D : le fond exact du produit
PANEL = (16, 36, 28)
ACCENT = (45, 212, 191)
TEXT = (236, 253, 245)
DIM = (107, 155, 138)

F_BOLD = r'C:\Windows\Fonts\segoeuib.ttf'
F_REG = r'C:\Windows\Fonts\segoeui.ttf'
f_title = ImageFont.truetype(F_BOLD, 92)
f_sub = ImageFont.truetype(F_REG, 40)
f_tiny = ImageFont.truetype(F_REG, 27)
f_sec = ImageFont.truetype(F_BOLD, 33)
f_cap = ImageFont.truetype(F_REG, 31)


def centered(d, y, txt, font, fill):
    w = d.textbbox((0, 0), txt, font=font)[2]
    d.text(((W - w) // 2, y), txt, font=font, fill=fill)


def card(title, sub, foot=None):
    im = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(im)
    centered(d, 405, title, f_title, TEXT)
    d.rectangle([W // 2 - 90, 535, W // 2 + 90, 538], fill=ACCENT)
    centered(d, 578, sub, f_sub, DIM)
    if foot:
        centered(d, 660, foot, f_tiny, ACCENT)
    return im


def shot(name, section, caption, crop=None):
    """Une capture, posée sur le fond du produit, avec sa section et UNE phrase."""
    path = os.path.join(SRC, name)
    if not os.path.exists(path):
        raise SystemExit(
            u"⛔ capture manquante : %s\n"
            u"   La séance de prise de vue n'a pas été faite, ou le fichier porte un autre nom.\n"
            u"   Voir market/screens/SHOTLIST.md. On ne fabrique PAS une vidéo avec des trous." % name)
    im = Image.new('RGB', (W, H), BG)
    s = Image.open(path).convert('RGB')
    if crop:
        s = s.crop(crop)
    # mise a l'echelle SANS deformer, dans la fenetre 1920x820
    fw, fh = W - 128, 820
    f = min(fw / float(s.width), fh / float(s.height))
    s = s.resize((max(1, int(s.width * f)), max(1, int(s.height * f))), Image.LANCZOS)
    im.paste(s, ((W - s.width) // 2, 110 + (fh - s.height) // 2))
    d = ImageDraw.Draw(im)
    # bandeau de section, en haut a gauche
    d.rectangle([0, 0, W, 74], fill=PANEL)
    d.text((64, 22), 'RC', font=f_sec, fill=ACCENT)
    d.text((64 + d.textbbox((0, 0), 'RC', font=f_sec)[2] + 40, 26), section, font=f_tiny, fill=DIM)
    # legende : une seule phrase, en bas, sur le fond
    d.rectangle([64, 962, 67, 1010], fill=ACCENT)
    d.text((96, 966), caption, font=f_cap, fill=TEXT)
    return im


SHOTS = [
    (card('RiskCockpit', 'A rule-monitoring dashboard for prop-firm traders',
          'MetaTrader 5   \u00b7   Indicators   \u00b7   Free'), 4.0),
    (shot('01-rail-and-topbar.png', 'ON THE CHART',
          'What stays on screen is a 36-pixel rail and the three numbers that decide the next click.'), 5.0),
    (shot('02-limits.png', 'LIMITS',
          'One gauge per rule \u2014 including the risk your firm scores, which a moved stop does not lower.'), 5.5),
    (shot('03-lot-advisor.png', 'LOT ADVISOR',
          'A lot size capped so that a losing trade cannot take the account past a limit.'), 5.5),
    (shot('04-news.png', 'NEWS WINDOWS',
          'Upcoming events in the next 24 hours, and whether your programme puts a rule on that window.'), 5.0),
    (shot('05-discipline.png', 'DISCIPLINE',
          'A self-lock you can arm and release, a hard lock at 80% of the daily cap, a cooldown after losses.'), 5.5),
    (shot('06-account-profile.png', 'PROGRAM',
          'Pick your programme, its phase and its size. Every limit on screen is derived from it.'), 4.5),
    (shot('08-built-in-manual.png', 'BUILT-IN MANUAL',
          'The help section is the documentation: a usage guide, then every element explained.'), 5.0),
    (card('It measures. You decide.', 'No order sent.  No signal.  No claim about profitability.',
          'Interface in English, French and Spanish'), 4.5),
]

FADE = int(0.4 * FPS)


def frames():
    """Chaque image de la video, dans l ordre, en RGB."""
    prev = None
    for img, secs in SHOTS:
        arr = np.asarray(img, dtype=np.float32)
        if prev is not None:                   # fondu enchaine : les coupes seches sautent aux yeux
            for k in range(FADE):
                a = k / float(FADE)
                yield (prev * (1.0 - a) + arr * a).astype(np.uint8)
        out = arr.astype(np.uint8)
        for _ in range(int(secs * FPS)):
            yield out
        prev = arr


def encode(vcodec, extra):
    """Un seul encodage : les images RAW entrent par le tube, le son par un fichier."""
    cmd = [FFMPEG, '-y',
           '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (W, H),
           '-r', str(FPS), '-i', '-',
           '-i', WAV,
           '-c:v', vcodec] + extra + [
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-shortest', OUT]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                         stderr=subprocess.PIPE)
    try:
        for f in frames():
            p.stdin.write(f.tobytes())
        p.stdin.close()
    except (BrokenPipeError, OSError):
        pass
    err = p.stderr.read().decode('utf-8', 'replace')
    p.wait()
    ok = (p.returncode == 0 and os.path.exists(OUT) and os.path.getsize(OUT) > 100000)
    return ok, err


def main():
    os.makedirs(VID, exist_ok=True)
    if not os.path.exists(WAV):
        print(u"⚠️ piste absente : lancer d'abord tools/build-market-music.py")
        return 1
    if not FFMPEG or not os.path.exists(FFMPEG):
        print(u"⚠️ ffmpeg introuvable — impossible de monter la vidéo.")
        return 1

    # H.264 d'abord : c'est ce que YouTube réencode le mieux, et sur du texte fin
    # la différence avec le MPEG-4 de l'ancienne chaîne est visible. On essaie les
    # encodeurs matériels dans l'ordre, puis MediaFoundation, puis le repli.
    err = ''
    for vcodec, extra, label in (
            ('h264_nvenc', ['-preset', 'p7', '-rc', 'vbr', '-b:v', '12M', '-maxrate', '16M'], 'NVIDIA'),
            ('h264_qsv',   ['-b:v', '12M'],                            'Intel QSV'),
            ('h264_amf',   ['-quality', 'quality', '-b:v', '12M'],     'AMD'),
            ('h264_mf',    ['-b:v', '12M'],                            'MediaFoundation'),
            ('mpeg4',      ['-q:v', '2'],                              'MPEG-4 (repli)')):
        ok, err = encode(vcodec, extra)
        if ok:
            total = sum(s for _, s in SHOTS) + FADE / float(FPS) * (len(SHOTS) - 1)
            print('video : %s' % OUT)
            print('%s / %s  |  %d x %d @ %d fps  |  %.1f s  |  %.1f Mo'
                  % (vcodec, label, W, H, FPS, total, os.path.getsize(OUT) / 1048576.0))
            return 0
        print(u"   %-12s indisponible" % vcodec)
    print(u"⛔ aucun encodeur n'a fonctionné :\n" + err[-1200:])
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
