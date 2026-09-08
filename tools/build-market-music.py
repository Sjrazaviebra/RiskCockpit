# -*- coding: utf-8 -*-
u"""Piste de la vidéo produit — v2. Reproche de JR : « on n'entend que quelques secondes au milieu,
le reste il n'y a rien, et on s'endort ».

Les deux défauts sont distincts et se corrigent séparément :
 1. **La présence.** Une nappe d'accords tenus a une enveloppe très creuse : elle monte, elle
    retombe, et entre deux accords il n'y a presque rien. D'où l'impression de silence.
    ⇒ On construit sur un ARPÈGE en croches continues : il y a une note toutes les 300 ms du début
    à la fin. Le script MESURE ensuite le RMS par seconde et REFUSE d'écrire si un creux dépasse
    ce qui est audible — c'est exactement le reproche, donc c'est ce qu'on vérifie.
 2. **L'élan.** « On s'endort » : il manquait une pulsation. On ajoute une basse par accord et une
    fine impulsion sur les temps. Ça reste discret : c'est un fond de vidéo produit, pas un morceau.

⛔ Synthétisée : ni revendication Content ID possible, ni attribution à porter. C'est ce qui a
coûté deux allers-retours aujourd'hui (une piste Pixabay revendiquée malgré l'absence de badge,
puis Fluidscape qui impose une attribution CC BY).
"""
import math
import os
import wave

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "market", "video", "RiskCockpit-track.wav")
SR = 44100
DUR = 47.7
BPM = 96.0
BEAT = 60.0 / BPM
STEP = BEAT / 2.0                      # croches

n = int(SR * DUR)
t = np.arange(n) / float(SR)
mix = np.zeros(n)


def note(freq, start, length, amp, kind='tri'):
    """Une note, avec attaque courte et chute douce - jamais de clic, jamais de tenue molle."""
    i0 = int(start * SR)
    ln = int(length * SR)
    if i0 >= n:
        return
    ln = min(ln, n - i0)
    tt = np.arange(ln) / float(SR)
    atk = max(1, int(0.008 * SR))
    env = np.exp(-tt * 3.4)
    env[:atk] *= np.linspace(0, 1, atk)
    if kind == 'tri':                  # triangle : doux, sans les harmoniques dures du carre
        w = (2.0 / np.pi) * np.arcsin(np.sin(2 * np.pi * freq * tt))
    else:                              # sinus pour la basse
        w = np.sin(2 * np.pi * freq * tt)
    mix[i0:i0 + ln] += amp * env * w


N = {'A3': 220.00, 'C4': 261.63, 'E4': 329.63, 'G4': 392.00, 'A4': 440.00,
     'C5': 523.25, 'E5': 659.25, 'F4': 349.23, 'D4': 293.66, 'B4': 493.88,
     'F3': 174.61, 'C3': 130.81, 'G3': 196.00, 'A2': 110.00, 'F2': 87.31, 'C2': 65.41, 'G2': 98.00}

# Am - F - C - G : ca avance, ca ne resout pas triomphalement. 4 accords x 2 mesures.
PROG = [
    (['A3', 'C4', 'E4', 'A4', 'E4', 'C4'], 'A2'),
    (['F3', 'A3', 'C4', 'F4', 'C4', 'A3'], 'F2'),
    (['C4', 'E4', 'G4', 'C5', 'G4', 'E4'], 'C2'),
    (['G3', 'B4', 'D4', 'G4', 'D4', 'B4'], 'G2'),
]

BARS = 2                                # 2 mesures de 4 temps par accord
bar_len = BEAT * 4
chord_len = bar_len * BARS
k = 0
pos = 0.0
while pos < DUR:
    arp, bass = PROG[k % len(PROG)]
    # basse : une note tenue par accord, discrete, elle porte sans se faire entendre
    note(N[bass], pos, chord_len * 0.95, 0.30, 'sin')
    # arpege continu : une croche toutes les ~312 ms, du debut a la fin -> jamais de trou
    s = pos
    j = 0
    while s < pos + chord_len and s < DUR:
        note(N[arp[j % len(arp)]], s, STEP * 1.9, 0.115)
        s += STEP
        j += 1
    # impulsion sur les temps : la pulsation qui manquait
    b = pos
    while b < pos + chord_len and b < DUR:
        i0 = int(b * SR)
        ln = min(int(0.05 * SR), n - i0)
        if ln > 0:
            tt = np.arange(ln) / float(SR)
            mix[i0:i0 + ln] += 0.035 * np.exp(-tt * 60) * np.random.RandomState(int(b * 100)).randn(ln)
        b += BEAT
    pos += chord_len
    k += 1

# fondus : entree courte (on veut la musique tout de suite), sortie longue vers le silence
fi, fo = int(SR * 1.2), int(SR * 3.5)
mix[:fi] *= np.linspace(0, 1, fi)
mix[-fo:] *= np.linspace(1, 0, fo) ** 1.5

mix = mix / np.max(np.abs(mix)) * 0.30

# ---- LE CONTROLE QUI REPOND AU REPROCHE : la piste est-elle presente PARTOUT ? ----
win = SR
rms = np.array([np.sqrt(np.mean(mix[i:i + win] ** 2)) for i in range(0, n - win, win)])
core = rms[2:-4]                                   # hors fondus d'entree et de sortie
ratio = core.min() / core.mean()
print('RMS par seconde (hors fondus) : min %.4f  moyenne %.4f  -> creux le plus bas = %.0f %% de la moyenne'
      % (core.min(), core.mean(), ratio * 100))
if ratio < 0.55:
    raise SystemExit('REFUS : la piste a un trou audible (%.0f %% de la moyenne). '
                     'C est exactement le defaut signale par JR.' % (ratio * 100))

pcm = (mix * 32767).astype('<i2')
with wave.open(OUT, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(np.repeat(pcm[:, None], 2, axis=1).tobytes())

print('piste : %s' % OUT)
print('%.1f s | %.0f BPM | arpege continu en croches | crete %.1f dBFS' % (DUR, BPM, 20 * math.log10(0.30)))
