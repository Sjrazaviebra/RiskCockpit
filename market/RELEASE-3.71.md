# Mise en ligne RiskCockpit 3.71 — MQL5 Market (produit 180509)

État : **le code, le binaire, les textes, les captures et la vidéo sont prêts.** Il reste deux
gestes que je ne fais pas moi-même, et ils sont écrits ici pour être faits une fois, sans chercher.

---

## 1. Ce qui est prêt, vérifié

| Élément | État | Preuve |
|---|---|---|
| Binaire `RiskCockpit.ex5` | **3.71** | `Result: 0 errors, 0 warnings` |
| Gate statique | **22/22** | `python tools/audit.py` |
| Contrôles positifs du gate | **20/20** + 2 non-couvertures déclarées | `python tools/gate_selftest.py` |
| Self-test des maths (dans MT5) | **37/37** | script `RC_SelfTest` |
| Format de version `major.minor` | `3.71` | exigé par le Market |
| Description EN / FR / ES | écrite, Part IV | `market/MARKET-DESCRIPTION.md` |
| Captures | **11**, 1680×1080, UI en anglais, login masqué sur la 06 | `market/screens/` |
| Icône | logo centralisé, sans numéro de version | `brand/RiskCockpit_logo_200.png` |
| Vidéo | **68,7 Mo**, H.264 12 Mb/s, 47,7 s, musique synthétisée | `market/video/RiskCockpit-overview.mp4` |

La vidéo est hors dépôt (`.gitignore`) : un `.mp4` de 68 Mo n'a rien à faire dans un dépôt de code.

## 2. Les deux gestes qui me sont fermés

### a. Téléverser la vidéo sur YouTube

L'outil de dépôt de fichier du navigateur **plafonne à 10 Mo par appel**, le fichier en fait
**68,7 Mo**. Ce n'est pas un réglage : c'est la limite de l'outil. Un ré-encodage ciblé qualité
(`-cq 20`, NVENC) a produit un fichier **plus gros** (79,9 Mo) — descendre sous 10 Mo voudrait dire
abîmer visiblement le texte de l'interface, qui est tout le sujet de la vidéo.

⇒ **JR dépose le fichier** dans YouTube Studio (Créer → Ajouter des vidéos → glisser le `.mp4`).
Ensuite je remplis le titre, la description, les tags, je passe la vidéo en **Non répertoriée** et je
relis le lien.

Titre, description et tags : section 4 ci-dessous.

### b. Supprimer l'ancienne vidéo

L'ancienne (`RiskCockpit – Prop Firm Risk Manager for MetaTrader 5`, non répertoriée, 8 juin 2026,
4 vues, `https://youtu.be/fGPhSNp0Qc`) doit disparaître de la fiche. **Je ne supprime pas de données
de façon définitive** — c'est un geste sans retour, il revient à JR. Si le but est seulement qu'elle
ne soit plus atteignable, je peux la passer en **Privée** : réversible, et le lien meurt tout de
même.

## 3. La séquence de mise en ligne (fiche 180509)

1. **Versions** → `Upgrade` → téléverser les SOURCES (le Market compile lui-même) :
   `Indicators/RiskCockpit.mq5`, `Libraries/*.mqh`, `Services/RCNewsFeeder.mq5`.
2. **Description** → coller EN / FR / ES depuis `market/MARKET-DESCRIPTION.md`.
3. **Screenshots** → remplacer les 11 images par `market/screens/01..11`.
4. **Logo** → `brand/RiskCockpit_logo_200.png`.
5. **Video** → remplacer `https://youtu.be/fGPhSNp0Qc` par le nouveau lien.
6. Envoyer à la validation.

⚠️ La fiche porte l'identité vendeur de JR. Je remplis, **je n'envoie pas** : le dernier bouton est
à lui, après relecture.

## 4. Textes YouTube

**Titre**
`RiskCockpit — prop-firm rule monitor for MetaTrader 5 (free indicator)`

**Description**

```
RiskCockpit is a free MetaTrader 5 indicator that watches the rules of a
prop-firm account: daily loss, overall loss, per-trade risk, margin, news
windows and trading days.

It measures. It does not trade: an indicator cannot send an order, and no
version of this panel ever will.

- one gauge per rule, including the risk your firm scores at the stop posed
  at opening
- a lot size capped so a losing trade cannot take the account past a limit
- upcoming events in the next 24 h, and whether your programme binds them
- a self-lock you can arm, a hard lock at 80% of the daily cap, a cooldown
  after losses
- interface in English, French and Spanish

Free on the MQL5 Market. Source code: github.com/Sjrazaviebra/RiskCockpit
```

**Tags** : `metatrader 5`, `mt5 indicator`, `prop firm`, `risk management`, `funded account`,
`trading discipline`, `position sizing`, `drawdown`

**Visibilité** : Non répertoriée. **Pas** de public « conçu pour les enfants ».
