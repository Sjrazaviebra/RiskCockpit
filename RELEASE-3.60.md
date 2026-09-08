# Mise en ligne RiskCockpit 3.60 — MQL5 Market (produit 180509)

État au moment d'écrire : **le code, le binaire, les textes, les icônes et la piste audio sont
prêts. Il manque les captures — et elles sont le seul point qui demande de piloter MT5.**

---

## 1. Ce qui est prêt, vérifié

| Élément | État | Preuve |
|---|---|---|
| Binaire `RiskCockpit.ex5` | **3.60** | `Result: 0 errors, 0 warnings` |
| Gate statique | **22/22** | `python tools/audit.py` |
| Contrôles positifs du gate | **20/20** + 2 non-couvertures déclarées | `python tools/gate_selftest.py` |
| Self-test des maths (dans MT5) | **37/37** | script `RC_SelfTest` |
| `#property` copyright / link / version / description / icon | présents | en-tête de `RiskCockpit.mq5` |
| Format de version `major.minor` | `3.60` | exigé par le Market |
| Description EN / FR / ES | écrite, Part IV | `MARKET-DESCRIPTION.md` |
| Icônes 200 / 140 / 60 | générées | `RiskCockpit_logo_{200,140,60}.png` |
| Piste audio de la vidéo | **47,7 s, sans trou** (creux à 81 % de la moyenne) | `market_video/RiskCockpit-track.wav` |
| Script de montage vidéo | écrit, refuse de tourner s'il manque une capture | `tools/build-market-video.py` |

## 2. Ce qui bloque, et pourquoi

### Les captures d'écran

Elles demandent d'ouvrir chaque section du panneau dans MT5, donc de **cliquer**. Le 08/09/2026,
une séance de vérification visuelle a coïncidé avec l'ouverture d'une position `SDRM-TEST` sur le
compte démo : ce commentaire n'est produit que par le bouton SELL de StrategyDeck, atteignable
uniquement par un clic. Sur un compte démo, StrategyDeck démarre **armé**.

⇒ **Avant la séance de captures, une action de JR : désarmer StrategyDeck** (un clic sur son bouton
ARMER), ou détacher son graphique. Un clic mal placé devient alors un refus affiché à l'écran au
lieu d'un ordre envoyé. Après ça, la séance suit `market_screens/SHOTLIST.md` : onze prises,
langue basculée sur EN au début et remise en FR à la fin.

### La vidéo YouTube

Je produis le fichier `.mp4` (image + son). **Je ne peux pas le téléverser** : je n'ai pas accès au
compte YouTube, et publier sur un service externe n'entre pas dans ce que je fais sans que JR le
demande explicitement pour cette action-là. Le téléversement, le réglage **« Non répertoriée »** et
le collage du lien dans la fiche restent à JR.

---

## 3. La séquence, dans l'ordre

1. **JR** : désarmer StrategyDeck (ou détacher son graphique).
2. **Moi** : séance de captures selon `SHOTLIST.md`, langue EN, puis remise en FR.
3. **Moi** : `python tools/prep_screens.py` — met les captures aux specs, refuse ce qui ne passe pas.
4. **Moi** : `python tools/build-market-video.py` — assemble l'image et colle la piste audio.
5. **JR** : téléverser la vidéo sur YouTube en **Non répertoriée**, récupérer le lien.
6. **JR** : sur mql5.com, produit **180509** → *Modifier* :
   - version → `3.60`
   - description EN / FR / ES → coller depuis `MARKET-DESCRIPTION.md`
   - icône → `RiskCockpit_logo_200.png` (et 140 / 60 si le formulaire les demande séparément)
   - captures → vider les anciennes, verser `market_screens/*.png`
   - vidéo → coller le lien YouTube
   - téléverser la **source** `RiskCockpit.mq5` + les `Libraries/*.mqh` + `Services/RCNewsFeeder.mq5`
     (le Market compile lui-même ; l'`.ex5` du dépôt n'est pas ce qui est publié)
7. Soumettre. La validation automatique prend une dizaine de minutes.

---

## 4. Textes YouTube

### Titre (EN)
```
RiskCockpit — prop-firm rule dashboard for MetaTrader 5
```

### Titre (FR)
```
RiskCockpit — tableau de bord des règles prop firm pour MetaTrader 5
```

### Description (EN)
```
RiskCockpit measures your account against the rules of your funding program while you trade.
It never opens, closes or modifies a position.

In this overview:
· what stays on the chart — a 36-pixel rail and three numbers
· one gauge per rule, each warning at its own threshold
· a lot size capped so a losing trade cannot take the account past a limit
· the countdown to the next binding news event, with the share of profit your program keeps
· the discipline ladder: self-lock, daily hard lock, cooldown after losses
· the built-in manual

Free on the MetaTrader 5 Market. Interface in English, French and Spanish.

No order is ever sent by this tool, no signal is produced, and no claim is made about
profitability.
```

### Description (FR)
```
RiskCockpit mesure ton compte face aux règles de ton programme de financement pendant que tu
trades. Il n'ouvre, ne ferme et ne modifie jamais une position.

Dans cette présentation :
· ce qui reste à l'écran — un rail de 36 pixels et trois chiffres
· une jauge par règle, chacune avec son propre seuil d'alerte
· une taille de lot bornée pour qu'un trade perdant ne fasse pas passer un plafond
· le compte à rebours de la prochaine news contraignante, avec la part de profit conservée
· l'échelle de discipline : auto-verrou, verrou journalier, pause après pertes
· le manuel intégré

Gratuit sur le MetaTrader 5 Market. Interface en anglais, français et espagnol.

Cet outil n'envoie jamais d'ordre, ne produit aucun signal, et ne fait aucune promesse de gain.
```

### Réglages de la mise en ligne
- Visibilité : **Non répertoriée** (obligatoire pour une vidéo de fiche Market)
- Public : *Non, ce n'est pas conçu pour les enfants*
- Catégorie : Science et technologie
- Mots-clés : `MetaTrader 5, MQL5, prop firm, risk management, trading dashboard, drawdown, position sizing`

⚠️ **La musique est synthétisée** par `tools/build-market-music.py` — aucune revendication Content
ID possible, aucune attribution à porter. C'est délibéré : une piste « libre de droits » trouvée
en ligne a déjà coûté deux allers-retours sur un autre produit.

---

## 5. Ce que la fiche NE doit pas contenir (rappel Part IV)

Aucune garantie ni promesse de bénéfice · aucun superlatif sur les fonctionnalités · aucun résultat
de backtest présenté comme du réel · aucun lien externe en guise de description · aucun titre
sensationnel · aucune image de mauvaise qualité. Inviter à laisser un avis est autorisé ; le
récompenser ne l'est pas.
