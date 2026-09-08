# Captures MQL5 Market — liste de prise de vue

**Règles techniques** : 12 maximum · ≥ 720 px sur un côté · ≤ 1920×1080 · ≤ 2 Mo · PNG/JPG/GIF.
`python tools/prep_screens.py` met tout aux specs et **refuse** ce qui ne peut pas y passer.

🔴 **La règle qui ne se vérifie qu'à l'œil : l'interface doit être en ANGLAIS.**
RiskCockpit retient la langue **par compte**. Il faut donc **basculer la langue sur EN avant la
séance** (barre du haut → pastille de langue, ou CFG → onglet AFFICHAGE → Langue), et la remettre
après. Une capture en français passe tous les contrôles techniques et se fait refuser à la
validation.

⚠️ **Aucune donnée de compte ne doit être lisible.** Le numéro de compte n'apparaît nulle part dans
le panneau, mais **la barre de titre de MT5 le porte** : on capture la **fenêtre du graphique**, pas
l'écran entier. Le solde apparaît dans la barre du haut de RiskCockpit — c'est un compte démo, mais
on recadre pour ne garder que ce que la capture doit montrer.

---

## Les onze prises

| # | Fichier | État de l'interface à préparer | Ce que la capture doit montrer |
|---|---|---|---|
| 01 | `01-rail-and-topbar.png` | Panneau **fermé**, rail seul + barre du haut | Ce qui reste à l'écran en permanence : un rail de 36 px et trois chiffres en haut. C'est l'argument d'encombrement. |
| 02 | `02-limits.png` | Rail → cellule **LIM** | Une jauge par règle, chacune avec son propre seuil d'alerte, et la distance au plafond le plus proche. |
| 03 | `03-lot-advisor.png` | Rail → cellule **LOT** | Le lot conseillé, la contrainte qui le borne, et le champ sélectionnable pour le copier. |
| 04 | `04-news.png` | Rail → cellule **NEWS** | Le compte à rebours du prochain événement contraignant, la part de profit conservée, la liste À VENIR. |
| 05 | `05-discipline.png` | Rail → cellule **DISC** | L'échelle de verrous : auto-verrou, verrou journalier, pause après pertes, détection de tilt. |
| 06 | `06-account-profile.png` | Rail → cellule **CPT** | La cascade de profil : plan → phase → taille → add-ons, et les plafonds qui en découlent. |
| 07 | `07-settings.png` | Rail → cellule **CFG** | Les quatre onglets de réglages, dont les contrôles verrouillés qui disent **pourquoi**. |
| 08 | `08-built-in-manual.png` | Rail → cellule **AIDE**, un volet ouvert | Le manuel intégré : le guide pas à pas, puis un volet par surface. |
| 09 | `09-full-sidebar.png` | Chevron du rail → barre latérale complète | Les huit sections empilées en accordéon. |
| 10 | `10-light-theme.png` | Barre du haut → pastille **D/L** | Le même panneau en thème clair. Trois palettes × clair/sombre. |
| 11 | `11-positions-table.png` | ⚠️ **exige une position ouverte** | La table flottante : âge, P&L, absence de stop. |

### ⚠️ La prise 11 et son coût

La table des positions n'existe à l'écran **que s'il y a une position ouverte**. Je ne l'ouvrirai
pas : le mandat dit « MT5 en lecture seule, jamais de trade », et ça vaut aussi pour une position
ouverte dans le seul but d'être photographiée.

Deux issues, au choix de JR :
1. **il ouvre lui-même** une petite position démo pendant la séance, je capture, il la ferme ;
2. **on publie sans la prise 11.** Dix captures suffisent largement, et la table est déjà visible
   en arrière-plan de la prise 01.

---

## Ordre de la séance (le plus court, le moins de clics)

1. Langue → **EN** (une fois).
2. `01` panneau fermé.
3. `02` → `08` : une cellule du rail par capture, dans l'ordre du rail — chaque clic ouvre la
   suivante, aucun aller-retour.
4. `09` chevron → barre complète.
5. `10` pastille D/L → thème clair, capture, re-clic pour revenir.
6. Langue → **FR** (l'état de départ de JR).

## Précaution de séance

🔴 **Le graphique StrategyDeck doit être hors d'atteinte pendant la séance.** Sur un compte démo,
StrategyDeck démarre **armé** : un clic qui atterrit sur son bouton SELL ouvre une position. C'est
exactement ce qui s'est produit le 08/09/2026 pendant une tentative de vérification visuelle.
Avant la séance : **désarmer StrategyDeck** (un clic sur son bouton ARMER), ou détacher son
graphique. Un clic mal placé devient alors un refus affiché, pas un ordre.
