# RiskCockpit — HISTORY

## 0. Build topology (established 2026-09-04, ÉTAPE 0)

**This section is the answer to "where does the build actually happen?". It is the first thing to
read after a fresh clone or a long break.**

### The constraint that decides everything

The source uses `#include <..\Libraries\X.mqh>`. The `<>` form resolves from
`<data folder>\MQL5\Include\`, so `<..\Libraries\X.mqh>` = `<data folder>\MQL5\Libraries\X.mqh`.
`#resource "RiskCockpit_logo.bmp"` resolves next to the `.mq5` itself.
⇒ **The project cannot be compiled from this repository.** It builds only inside an MT5 data
folder that holds the includes and the resource in those exact places.

### Retained topology

| Role | Path |
|---|---|
| Build tree (MT5 data folder) | `%APPDATA%\MetaQuotes\Terminal\<TERMINAL-ID>\MQL5\` |
| Compiled source | `…\MQL5\Indicators\mql5_market\RiskCockpit\RiskCockpit.mq5` |
| Includes (all five) | `…\MQL5\Libraries\` : `CChallengeProfileCatalog.mqh`, `CPyramidEngine.mqh`, `JR_CanvasUI.mqh`, **`RC_Math.mqh`**, `RC_ShellUI.mqh` |
| Embedded resource | `RiskCockpit_logo.bmp`, next to the `.mq5` |
| Output | `RiskCockpit.ex5`, same folder |
| Companion service | `…\MQL5\Services\RCNewsFeeder.mq5` |

Verified by the compiler log itself (each `including …` line points into
`…\D0E8209F…\MQL5\Libraries\`), not by inspection.

**Note on the second MQL5 tree.** `…\MQL5\Experts\RoboScalperV1 - JR\MQL5\` is a *complete but
separate* MQL5 tree (the `jr-mql5-source` repository). It carries its own copies of
`CChallengeProfileCatalog.mqh` and `CPyramidEngine.mqh`, which is what made the topology
ambiguous. **It is not RiskCockpit's build tree** — no include in the build log comes from it.
Its `Indicators\mql5_market\RiskCockpit\RiskCockpit.mq5` and the build tree's one are the **same
physical file** reached by two paths (identical md5, a single edit changes both). Either path may
be edited; they are one file.

Two `.mqh` were missing from `MQL5\Libraries\` on 2026-09-04 (catalog + pyramid engine) and were
copied in to complete the tree. Without them the build tree was incomplete.

### Direction of synchronisation (decided 2026-09-04)

**Terminal → repository.** The build tree is the live source: it is where edits are made and the
only place the compiler runs. The repository is the versioned mirror; files are copied
terminal → `F:` **at commit time**, md5-verified, then committed and pushed.

(The Coordinator's older note — "the conversation edits the terminal, the Coordinator syncs
terminal → F:" — is confirmed, with one change: **this conversation now owns the whole loop**,
including the compile, the commit and the push.)

| Repository path | Build-tree path |
|---|---|
| `Indicators/RiskCockpit.mq5` | `MQL5\Indicators\mql5_market\RiskCockpit\RiskCockpit.mq5` |
| `Libraries/JR_CanvasUI.mqh` | `MQL5\Libraries\JR_CanvasUI.mqh` |
| `Libraries/RC_ShellUI.mqh` | `MQL5\Libraries\RC_ShellUI.mqh` |
| `Libraries/CChallengeProfileCatalog.mqh` | idem |
| `Libraries/CPyramidEngine.mqh` | idem |
| `Libraries/RC_Math.mqh` | idem |
| `Scripts/RC_SelfTest.mq5` | `MQL5\Scripts\RC_SelfTest.mq5` |
| `Services/RCNewsFeeder.mq5` | `MQL5\Services\RCNewsFeeder.mq5` |

*(v3.58 : cette table en oubliait deux — `RC_Math.mqh`, qui porte les fonctions pures et
le sixième `#include` de la source, et le script de self-test. Reconstruire l'arbre depuis
l'ancienne table donnait un arbre qui ne compile pas.)*

### Compiling (autonomous, no keyboard F7)

```powershell
Start-Process -FilePath "C:\Program Files\MetaTrader 5\metaeditor64.exe" `
  -ArgumentList "/compile:`"<source.mq5>`"","/log:`"<log>`"" -Wait -PassThru -NoNewWindow
```

⚠️ **The exit code is anti-correlated and proves nothing** (this working form returns `1`; the
forms that compile nothing return `0`). The only two proofs are the **`Result:` line of the log**
and the **`.ex5` timestamp**. The log is **UTF-16**: read it with
`open(p,'rb').read().decode('utf-16', errors='ignore')` — a plain `grep` returns nothing and lies.

---

## 1. Versioning

`X.YZ.AB`, cumulative, never reset. `#property version` carries `X.YZ`; the git tag carries
`X.YZ.AB`. The version is bumped **before** each compile, so that no two binaries ever share a
number.

Floor: **v2.13.05**. (`2.02` is the version published on the MQL5 Market; the repository is far
ahead of it — the `v2.02.05` and `v2.13.05` commits are marked *git-only*, never published.)

---

## 2. Log

## 3.x — the v3 shell becomes the interface

### v3.62.74 — le verrou gelait le réglage qui le CAUSE

Trouvé en le vivant. En préparant les captures, j'ai basculé le profil de
« Personnel » à « Stellar 1-Step 6K ». Sur un profil à 6 000 $, la perte déjà
réalisée de la journée fait **86 % du plafond journalier** : le verrou
journalier s'arme — exactement comme prévu. Et à partir de là **la cascade de
profil est refusée**, donc le réglage ne peut plus être corrigé. **Enfermé dans
une configuration fausse par une règle que cette configuration venait de
créer.**

Le verrou est **consultatif** : l'indicateur n'a aucune fonction de trading et
ne bloque aucun ordre. Geler la cascade n'empêche donc **rien de réel** — le
trader peut toujours prendre le trade. Ce que ça empêche, c'est que le panneau
dise la vérité sur le compte. **La déclaration du programme ne doit pas être
verrouillée par la règle qu'elle définit.** Restent gelés, et c'est voulu : les
steppers (ils desserrent les réglages de risque *courants*), les add-ons, les
bascules de configuration, les deux cases de violation, l'auto-verrou, et la
croix qui retire l'outil.

⭐ **Le gate PLANTAIT au lieu de rendre un verdict.** En versant la vidéo dans le
dépôt, le contrôle de fuite est tombé sur un `.mp4` absent de sa liste
d'extensions binaires : il a tenté de le décoder en UTF-8 et s'est arrêté sur
une exception. **Un gate qui plante ne dit ni oui ni non** — c'est pire qu'un
gate qui échoue, parce qu'on committe par-dessus sans s'en apercevoir, et c'est
exactement ce qui s'est passé. La liste d'extensions devient un raccourci ;
c'est désormais la **décodabilité** qui tranche, et ce qui n'est pas lisible en
texte est écarté *et compté comme tel*.

### v3.64.76 — un clic dans un menu ne le ferme plus, et les repères news passent dessous

- 🔴 **« Si je clique sur un menu il ne faut pas que ça se ferme. »** Un clic
  dans le panneau qui ne tombait sur **aucune zone enregistrée** le refermait.
  Or un panneau est plein d'espace mort : entre deux lignes, sur un titre de
  section, dans une marge. On vise une valeur, on manque de trois pixels, et la
  surface disparaît — **on apprend à cliquer avec précaution dans un outil fait
  pour être consulté vite.** Le repli automatique n'a de sens que pour un clic
  *ailleurs*, sur le graphique. (Ce défaut m'a refermé le panneau six fois
  pendant la séance de captures : je l'avais pris pour de la maladresse.)
- 🔴 **Les repères news du graphique passaient par-dessus le panneau.** Les
  étiquettes de la frise — « ▼ USD », « ◆ EUR » — étaient créées avec
  `OBJPROP_BACK` à `false`, donc au **premier plan** : MT5 les peint **après**
  le bitmap du panneau et elles s'impriment dessus. Les traits verticaux de la
  même fonction, eux, sont déjà en arrière-plan. Un repère décoratif posé sur le
  prix ne doit jamais recouvrir la surface qu'on lit. **C'est la leçon de la
  v3.24** : ce n'est pas un problème de z-order, c'est un problème d'**ordre de
  peinture**.

### v3.65.77 — la table flottante « perd un peu la place », et c'est mesurable

Elle était dimensionnée pour des polices de 7 à 9 points. La v3.63 les a toutes
montées d'un point — environ 13 px de haut au lieu de 12 — et sa géométrie ne
suivait pas : la bande d'accès rapide écrit sa valeur **11 px** sous son
libellé, donc « 0.01 » mordait sur la première position ; et une ligne de
position écrit le symbole à `y` et l'âge à `y + 14`, avec le P&L à droite de la
première ligne et le bouton CLOSE à droite de la seconde — à 14 px d'écart,
**« +2.68 » et « CLOSE × » se chevauchaient**. La table passe à 296 px, la bande
et les lignes gagnent leur interligne. Aucune couleur, aucun texte, aucun
comportement ne change : c'est de la place, rien d'autre.

### v3.67.79 — un compte personnel n'a pas de taille à choisir : il a des dépôts

JR : *« le compte réel de perso n'a pas de size prédéfini donc c'est auto, en gros
il faut voir les dépôts sur le compte, parce que je ne vois pas le compte réel
sur perso »*. Trois choses, la même idée que la v3.63 poussée jusqu'au bout.

- **La ligne « Taille » proposait treize valeurs sur un compte personnel** —
  Auto, puis 5K, 10K, 15K… jusqu'à 200K. Un compte personnel n'a pas de palier :
  il a le capital qu'on y a mis. **Choisir « 25K » sur un compte qui en contient
  10 000 ne décrit rien, ça fabrique des plafonds faux.** Il ne reste qu'Auto,
  donc plus de flèches : la valeur est une **constatation**, pas un choix.
- **On ne voyait pas le compte réel.** « Auto » ne disait pas de quoi. La ligne
  affiche maintenant le montant détecté — **« Auto 10000 $ »** — la référence
  dont *tous* les plafonds du profil personnel découlent.
- 🔴 **Et la détection ne voyait que le PREMIER dépôt.** `DetectStartingBalance`
  rendait le premier mouvement de balance positif et s'arrêtait là : un compte
  alimenté en deux fois — 10 000 puis 5 000 — était traité comme un compte de
  **10 000**, donc avec des plafonds calculés sur les **deux tiers** du capital
  réel ; et un **retrait** n'était pas compté du tout. On somme désormais tous
  les mouvements de balance, dépôts moins retraits : le capital réellement
  engagé.

**Vérifié à l'écran** : `Size : Auto 10000 $`, sans flèches, sur le profil
Personnel.

**Gate : 22 contrôles, 0 en échec. Compilation : 0 erreur, 0 avertissement.**

### v3.66.78 — « c'est quoi ROOM et comment c'est calculé ? »

JR a écrit le produit et ne sait pas ce que dit **le chiffre le plus en vue de
la barre du haut**. Aucun acheteur ne le saura. Deux causes, les deux réparées.

- 🔴 **Les trois pastilles de la barre partageaient une seule zone.** ROOM, LOT
  et NEWS étaient toutes enregistrées sous `RZ_NAV_VITALS` — la zone de
  l'equity. Survoler « ROOM » répondait donc *« Vitals : equity courante et
  positions ouvertes »*, qui parle d'autre chose. **Les trois chiffres que la
  barre existe pour donner avaient une aide qui ne les concernait pas.**
- **Le texte ne disait pas le calcul.** *« Dollars avant la limite active la
  plus proche »* nomme la chose sans dire comment on l'obtient. L'infobulle et
  la ligne du manuel portent maintenant la formule : **(% du plafond − %
  consommé) × la taille du programme**, sur la limite **journalière** ou
  **totale**, celle des deux qui est la plus proche.
- Et les trois pastilles **ouvrent la section correspondante**, comme les trois
  cellules de la table flottante : du chiffre au détail qui est derrière.

⭐ **Le gate a dit NON trois fois sur cette version — et il avait raison deux fois
sur trois.** (1) Les trois nouvelles zones étaient **dessinées sans être
traitées** : elles seraient tombées dans le repli automatique — exactement le
défaut que ce contrôle existe pour attraper, trouvé sur mon propre code une
heure après que j'aie écrit à quoi il sert. (2) Deux entrées i18n écrites en
fragments concaténés sur plusieurs lignes étaient **« NON ANALYSÉES »** : le
contrôle refuse de conclure au lieu de les déclarer propres. (3) La troisième
alerte était **fausse, et le défaut était dans l'instrument** : le contrôle des
séries comptait les identifiants de l'énumération **sans retirer les
commentaires**, et mon commentaire explicatif mentionnait `RZ_NAV_VITALS` — un
id fantôme. Un contrôle qui lit un commentaire comme du code ne mesure pas ce
qu'il annonce. Corrigé.

🔎 **Et une régression de fond, reproduite, qui n'est PAS une erreur de JR.**
*« À chaque fois que tu compiles, l'app oublie les settings. »* Mesuré :
**avant** rechargement `FundedNext / Stellar 2-Step / Funded / $6K`, **après**
`Personal`. Le discriminant est net — la **langue** et le **thème** survivent,
le **plan**, la **taille**, la **phase** et le **type de compte** non. Or les
premiers passent par `GlobalVariableSet` direct, les seconds par `GVSetLogin`,
la variante par login. `GlobalVariableSet` rend un booléen que ce code
**ignorait** : un échec d'écriture — MT5 en a plusieurs causes silencieuses,
dont un magasin de variables globales saturé (4096 au maximum, et **depuis la
v3.53 ce produit en crée une par ticket**) — ne laissait aucune trace. Le
réglage semblait pris, l'écran le montrait, et il disparaissait au rechargement.
**On ne devine pas la cause : on la rend visible.** L'écriture est vérifiée et
un échec s'écrit au journal avec sa clé et son code d'erreur.

**Gate : 22 contrôles, 0 en échec. Contrôles positifs : 20/20. Compilation :
0 erreur, 0 avertissement.**

### v3.63.75 — ne pas proposer ce qui n'existe pas

Trois demandes de JR, à l'usage, sur la même idée.

- **« S'il n'y a pas de proposition, il ne faut pas de boutons de changement. »**
  Les cinq lignes de la cascade portaient **toujours** leurs deux flèches, même
  quand la liste ne contenait qu'une seule valeur : sur FTMO, E8, The5ers,
  MyFundedFX et Personnel la ligne « Type » n'a qu'un choix, et le type de compte
  d'un compte personnel est **détecté** (démo ou réel), pas choisi. **Un bouton
  qui ne change rien apprend à ne plus faire confiance aux boutons.** Les flèches
  n'apparaissent — et la zone cliquable n'est posée — qu'à partir de deux valeurs.
- 🔴 **« Un compte perso n'a pas de challenge, pourquoi il y a des
  propositions ? »** La ligne « Phase » proposait Challenge P1 / P2 / Funded sur
  un compte personnel, qui n'a aucune des trois. Même défaut, plus discret, sur
  le **Stellar 1-Step** : il proposait une « Challenge P2 » qui n'existe pas dans
  un plan en **une** étape. La liste des phases est maintenant **dérivée du
  plan** — et le pas ne parcourt plus les quatre valeurs de l'énumération.
- **« La taille des polices est trop petite. »** Toutes les tailles gagnent un
  point, le grand chiffre en gagne deux, et le panneau s'élargit de 340 à 360 px.
  Les pas verticaux ne bougent pas : à 96 ppp, 10 pt fait environ 13 px de haut
  dans un pas de 18 px — la place manquait en largeur, pas en hauteur.

**Vérifié à l'écran** sur le profil Personnel : *Broker* garde ses flèches (six
enseignes), *Type* et *Type de compte* n'en ont plus, *Phase* affiche un tiret,
*Taille* garde les siennes.

**Gate : 22 contrôles, 0 en échec. Compilation : 0 erreur, 0 avertissement.**

### v3.61.73 — trois défauts trouvés par JR à l'usage

- 🔴 **Le défilement s'affichait même quand tout tenait.** *« s'il y a la place,
  pour quoi je dois avoir le défilement ? »* — il a raison, et le calcul était
  faux : je comparais la hauteur du contenu à `H − 26`, la réserve de
  l'indicateur. Or **quand la section tient, la surface est dimensionnée au
  contenu** : `H` vaut exactement le contenu, donc `contenu > H − 26` est **vrai
  par construction**. Les deux chevrons et la barre « défilement 0 % »
  s'affichaient sur un panneau qui n'avait rien à faire défiler — un contrôle
  qui ne sert à rien apprend au lecteur à ignorer les contrôles. On compare à la
  hauteur réelle, et la réserve ne s'ajoute que lorsqu'il y a vraiment
  débordement. **Vérifié à l'écran** : section DISCIPLINE, en-tête sans chevrons,
  pas de barre ; section AIDE sur un petit graphique, chevrons présents.
- 🔴 **La liste des news disparaissait sur un profil sans règle news.** La v3.37
  avait raison de ne pas inventer une règle qui n'existe pas — mais elle sortait
  de la fonction **avant** la liste « À VENIR ». Un événement économique ne cesse
  pas d'exister parce que le programme ne le sanctionne pas : le trader perdait
  le **calendrier** en même temps que la **règle**. Les deux sont maintenant
  séparés — la règle dépend du profil, le calendrier non — et la colonne de
  droite dit le niveau d'impact quand aucune règle ne s'applique.
- 🔴 **La classification FundedNext s'appliquait à tous les profils.** Le flux
  ForexFactory porte la table des événements **restreints de FundedNext**. Il
  pilotait la règle et l'affichage **quel que soit le plan choisi** : un compte
  FTMO, E8, The5ers ou personnel se voyait appliquer la classification d'une
  autre firme — avec sa couleur, son compte à rebours et sa part de profit. La
  source FN ne sert désormais de source de règle **que sur un plan FundedNext** ;
  partout ailleurs, c'est le calendrier MetaTrader. **Vérifié à l'écran** : sur
  le profil Personnel, la section AIDE affiche « Source : MT5 » et la liste porte
  « high » / « medium » au lieu d'une part de profit.

**Gate : 22 contrôles, 0 en échec. Compilation : 0 erreur, 0 avertissement.**

### v3.60.72 — préparation de la mise en ligne Market

**L'en-tête du fichier décrivait un autre logiciel.** Les vingt premières lignes
sont ce qu'un validateur MQL5 lit en premier — et elles annonçaient
*« T6 (this commit): UI skeleton + panel rendering »* pour un squelette remplacé
deux fois depuis, *« T7 (next commit): live rule evaluation »* pour un travail
fait depuis longtemps, et surtout **« The companion EA (V2) executes
auto-fixes »** : une promesse de fonctionnalité, dans un dépôt **public** et dans
la source soumise au Market, pour un EA qui n'existe pas. L'en-tête dit
maintenant ce que le fichier fait — et ce qu'il ne peut pas faire : aucune
fonction de trading n'y existe.

**Les pièces de la fiche Market, préparées et vérifiées :**

- `market/MARKET-DESCRIPTION.md` — la description en EN / FR / ES, écrite contre les
  règles officielles Part IV : aucune garantie ni promesse de bénéfice, aucun
  superlatif, aucun backtest, aucun lien externe.
- **Les icônes 200 / 140 / 60** — et la ligne **« v1.30 » effacée du logo**. Le
  logo publié portait une version de deux versions majeures en arrière, imprimée
  dans l'image : c'est ce qu'un acheteur voit **avant** de lire quoi que ce soit,
  et ça dit « abandonné ». Rien n'oblige à graver une version sur une icône — il
  faudrait la redessiner à chaque mise à jour, c'est-à-dire recréer le problème.
- `market/screens/SHOTLIST.md` — les onze prises, l'état de l'interface à
  préparer pour chacune, et la règle qui ne se vérifie qu'à l'œil : **l'interface
  doit être en anglais**, et RiskCockpit retient la langue par compte.
- `tools/prep_screens.py` — met les captures aux spécifications (≥ 720 px sur un
  côté, ≤ 1920×1080, ≤ 2 Mo) et **refuse** ce qui ne peut pas y passer, au lieu
  de produire un fichier rejeté à la soumission.
- `tools/build-market-music.py` — la piste, **synthétisée** : 47,7 s, ni
  revendication Content ID possible, ni attribution à porter. Le script **mesure
  le niveau seconde par seconde et refuse d'écrire** si un creux dépasse ce qui
  est audible (mesuré : creux le plus bas à 81 % de la moyenne).
- `tools/build-market-video.py` — le montage, sur la palette **échantillonnée sur
  le produit** et non choisie. Il **refuse de tourner s'il manque une capture** :
  on ne fabrique pas une vidéo avec des trous.
- `market/RELEASE-3.60.md` — la séquence de mise en ligne, ce qui est prêt, et ce qui
  ne l'est pas.

⭐ **Le gate a attrapé une fuite dans MON propre outillage** : j'avais écrit en
dur un chemin absolu portant le nom d'utilisateur Windows dans le script de montage —
exactement ce que le contrôle « fuite de données perso » existe pour trouver, et
il l'a trouvé sur mon code. Le chemin est désormais construit à l'exécution
depuis les variables d'environnement : le fichier ne porte plus aucun nom
d'utilisateur.

⚖️ **Ce qui n'est PAS fait, et pourquoi** : les captures. Elles demandent
d'ouvrir chaque section dans MT5, donc de cliquer. Le 08/09/2026, une séance de
vérification visuelle a coïncidé avec l'ouverture d'une position `SDRM-TEST` sur
le compte démo — un commentaire que seul le bouton SELL de StrategyDeck produit,
et qui n'est atteignable que par un clic. Sur un compte démo, StrategyDeck
démarre **armé**. La séance de captures attend donc un désarmement, pour qu'un
clic mal placé devienne un refus affiché et non un ordre envoyé.

**Gate : 22 contrôles, 0 en échec. Compilation : 0 erreur, 0 avertissement.**

### v3.59.71 — le panneau défile : le guide d'utilisation devient atteignable

🔴 **Le manuel était inatteignable sur un écran de portable.** La section AIDE
dessine, **avant** le manuel et **sans possibilité de replier**, un préambule
fixe d'environ **230 px** (COULEURS, RÈGLE NEWS, MARGE DE SURVIE). Les dix
volets repliés ajoutent 230 px, puis À PROPOS et les deux lignes lecture seule :
**le manuel FERMÉ mesure déjà ~618 px**. Ouvrir le premier volet — le guide
pas-à-pas, huit entrées dont trois dépassent 150 caractères — ajoute ~540 px,
soit **~1 160 px au total**.

La hauteur, elle, est plafonnée par le graphique (`m_sideH = m_chH − 24`). Sur
un portable 1366×768, MT5 maximisé avec la fenêtre Terminal ouverte —
**la configuration par défaut de MT5** — la zone graphique fait ~400 px : le
panneau en fait **376**. Il n'existait **aucun décalage de défilement**, un clic
sous le bitmap était **explicitement rejeté**, et le seul recours proposé était
une ligne de texte : *« sections : agrandis la fenêtre »*.

Autrement dit : **le guide d'utilisation écrit pour le débutant était, sur la
machine du débutant, illisible au-delà du premier tiers** — et la seule réponse
de l'outil était de lui demander un écran plus grand.

**Le panneau défile maintenant.** Deux chevrons dans l'en-tête, une page par
clic avec recouvrement, un indicateur de position en bas, et les chevrons
s'éteignent aux extrémités. Trois pièges traités au passage, parce que faire
défiler un panneau dessiné sur un bitmap n'est pas seulement soustraire un
décalage :

- **L'en-tête est peint EN DERNIER** — il recouvre le contenu qui remonte
  derrière lui — mais **ses zones cliquables restent enregistrées EN PREMIER** :
  le test d'impact retient le **premier** rectangle trouvé, donc un contenu passé
  sous l'en-tête ne peut pas voler le clic de la croix de fermeture.
- **Toute zone entièrement remontée sous l'en-tête est retirée de la liste.**
  Une zone invisible qui répond encore au clic est un piège, pas une commande.
- **La hauteur demandée se mesure hors défilement.** Sans ça, descendre réduirait
  la hauteur demandée, la surface rétrécirait, et on retrouverait exactement
  l'oscillation d'une image sur deux corrigée en v3.28.

⚖️ **Ce que je n'ai pas touché** : le panneau **complet** (les huit sections
empilées) garde son accordéon et son message « +N : replie une section ». Il a
déjà un mécanisme pour ce qui ne rentre pas ; lui ajouter un second aurait
demandé de refaire sa logique de croissance, celle-là même qui a oscillé en
v3.28. Le défilement couvre la vue **une section à la fois**, celle dans
laquelle on lit le manuel.

**Gate : 22 contrôles, 0 en échec. Contrôles positifs : 20/20 + 2
non-couvertures déclarées. Compilation : 0 erreur, 0 avertissement.**

### v3.58.70 — 7e lot : la lisibilité des jauges, et le code qui tournait pour personne

- 🔴 **Sur les trois thèmes CLAIRS, la piste des jauges rendait le niveau
  illisible.** La recette était « mélanger le FOND vers le NOIR » — ce qui ne
  donne une piste discrète que si le fond est sombre. Sur un thème clair la
  piste devenait un gris moyen (#9CA4A2) pendant que les remplissages des
  thèmes clairs sont, eux, des couleurs **sombres**. Contraste rempli/vide
  mesuré : **ambre 1,19:1**, vert 1,41:1, rouge 2,06:1 — le minimum pour un
  élément graphique porteur d'information est **3:1**, et le **même composant
  fait 10,2:1 en sombre**. Une jauge à 15 % et la même à 85 % renvoyaient la
  même impression : on perdait le **niveau**, c'est-à-dire exactement ce que la
  jauge existe pour donner. La jauge verticale du rail — **la seule lecture
  permanente quand le panneau est fermé** — subissait la même perte. En thème
  clair, la piste est désormais la surface elle-même (3,2 à 4,8:1 avec les trois
  remplissages) et un liseré la délimite du panneau.
- **La pastille MARGE/ROOM de la barre du haut se chevauchait en FR et en ES.**
  Largeur **fixe** à 86 px, **aucun texte mesuré** — alors que le kit expose
  `TextSizeGet`. Le libellé part à gauche, la valeur finit à droite : 72 px
  utiles. « MARGEN » + « $12.5K » en demandent 79 : le « $1 » de la valeur
  s'imprimait **par-dessus** le « EN » du libellé ; en français, les deux
  glyphes se touchaient. C'est le chiffre que cette barre existe pour donner —
  *est-ce que je peux prendre ce trade* — illisible dans deux langues sur trois.
  La pastille se mesure ; plancher à 86 px, donc la barre anglaise ne bouge pas.
- **Cinq des sept champs du registre des règles étaient écrits à chaque
  rafraîchissement et lus par personne**, sous un commentaire qui nommait un
  consommateur supprimé en v3.47 (« la ONE source dont le message Telegram est
  construit »). Pire, `label` portait onze libellés **anglais** — une seconde
  liste, contradictoire avec la table i18n dont le panneau tire réellement ses
  textes, qu'un relecteur pouvait prendre pour la source de vérité. Le registre
  ne porte plus que ce à quoi il sert : la clé et le statut.
- **Une liste d'add-ons était construite deux fois par seconde puis jetée** ; son
  seul lecteur, le pied de l'ancien panneau, est mort en v3.06. Le commentaire
  qui le nommait, lui, avait survécu.
- **`VolDigits` et `MonthShort` : deux fonctions complètes, jamais appelées.**
  La première **duplique** `LotDigits` avec un résultat **différent** : sur un
  pas crypto de 0,00001 l'une rend 5 et l'autre 4 — c'est-à-dire « 0.00 » à la
  place du lot. Deux réponses au même calcul dans le même fichier, dont une
  fausse et morte.
- **`ComputeNewsStats` réallouait quatre tableaux d'un cran par événement**
  (des centaines par balayage) et **construisait une ligne de journal à chaque
  rencontre deal × événement** — deux `TimeToString` et huit concaténations —
  pour un unique lecteur, derrière un drapeau dont la valeur par défaut est
  `false`. Réservation unique, journal construit seulement quand quelqu'un le lit.
- **Deux chiffres de documentation avaient dérivé** : la section « Build
  topology » — qui se présente comme *la première chose à lire après un clone* —
  annonçait « Includes (all four) » pour **cinq** includes (`RC_Math.mqh`
  manquait, ainsi que le self-test dans la table de synchronisation :
  reconstruire l'arbre depuis cette table donnait un arbre qui **ne compile
  pas**) ; et le README annonçait « Eleven static checks » quand le gate en
  exécutait 21.

⭐ **Le 22e contrôle tient ce dernier chiffre** : il compare le nombre écrit dans
le README au nombre de contrôles réellement exécutés. Il se place en dernier et
se compte lui-même. Un chiffre faux sur la première page d'un dépôt public est
ce qui décide si le lecteur fait confiance au reste.

**Gate : 22 contrôles, 0 en échec. Contrôles positifs : 20/20 + 2 non-couvertures
déclarées. Compilation : 0 erreur, 0 avertissement.**

### v3.57.69 — 6e lot : ce que l'écran DIT

- 🔴 **La liste « À VENIR » annonçait « règle 40% » là où le profil VOIDE
  100 % du profit.** Le libellé était **écrit en dur** alors que la même section
  lit la vraie part du profil quinze pixels plus haut. Trois profils du
  catalogue mettent cette part à **zéro** — FTMO 2-Step funded, E8, MFF : le
  profit réalisé dans la fenêtre news est **entièrement annulé**. Le panneau
  affichait donc simultanément, à dix-sept pixels d'écart : « ACTIVE - profit
  éligible 0% », « elig +0.00 », « seuls 0% du profit comptent » — et, juste
  en dessous, chaque événement rouge étiqueté **« règle 40% »**. Sur la surface
  faite pour décider si on prend le trade, et **dans le sens qui minimise la
  pénalité**. Le chiffre vient maintenant du profil.
- **Un seul clic refusé effaçait définitivement l'identité du verrou.** Le
  bandeau affiche « VERROU DISCIPLINE — Verrou journalier — 45 min restantes ».
  Réflexe du débutant : cliquer la croix pour retirer l'outil. Le clic est
  refusé — c'est voulu — mais le drapeau qui le note n'était remis à zéro **que
  dans `Init()`**, donc à l'attache. À partir de ce clic, et pour le reste de la
  session, le bandeau ne disait plus que « VERROUILLÉ — ce contrôle est
  désactivé ». Le trader avait perdu **quel** verrou le tient et **combien** de
  temps il reste, sur la seule surface conçue pour être impossible à manquer.
  Un refus est un **accusé de réception** : il dure quatre secondes, puis le
  bandeau redit ce qui compte.
- **Le manuel garantissait que le son est « toujours actif sur un plan prop ».**
  Ni la bascule (dessinée déverrouillée) ni l'hôte (qui l'inverse sans le
  moindre test) ne le font. La phrase avait été reprise de l'entrée du dessous —
  celle des outils de risque, où la promesse **est** tenue par un verrou — sans
  reprendre le verrou. C'est la **documentation** qui est corrigée, pas le code :
  imposer du son à quelqu'un qui a besoin de silence n'est pas le rôle d'un
  outil consultatif, et les alertes à l'écran, elles, ne s'arrêtent jamais.
- **Quatre chaînes échappaient à l'i18n.** Un `" en "` **français en dur** au
  milieu de la ligne TILT — un anglophone lisait « 6 en 15 min » ; un `"perte"`
  **français en dur** dans le conseiller de panier, à côté d'un `" add "`
  **anglais en dur**, sur une ligne pourtant assemblée fragment par fragment
  avec `Tr()` ; et « LOT » écrit en dur dans le rail et la table flottante là
  où la navbar dit « LOTE » — pour **le même nombre**.
- **L'annotation SL posée sur le graphique était anglaise en dur — mais son
  suffixe d'alerte, lui, était traduit.** La seule ligne d'avertissement dessinée
  sur le prix s'affichait donc **mi-anglaise mi-française**. Et la version
  entièrement traduite existait déjà : elle était écrite dans la propriété
  `OBJPROP_TEXT` d'une ligne horizontale **masquée**, que personne n'affiche
  jamais.
- 🔴 **Onze contrôles survolables n'avaient jamais eu de traduction poussée.**
  La coquille porte un texte de repli **en anglais** par zone ; l'hôte pousse
  les trois langues par-dessus. Onze zones n'avaient aucun accesseur : leur
  aide restait en anglais en français comme en espagnol — dont **l'auto-verrou,
  qui arme un STOP de plusieurs heures**, et sa libération. Un accesseur par
  zone (jamais une plage : une insertion ne peut plus décaler la série).
- **Deux orthographes espagnoles côte à côte.** « GUIA DE USO » se dessinait à
  vingt-trois pixels de « GUÍA DE USO » — les deux mêmes mots, deux graphies,
  l'une sous l'autre. Et l'onglet « AVANCE » (une progression) est devenu
  « AVANCÉ », le nom que le manuel du même produit lui donne déjà.

⭐ **Le gate a appris la classe** (21e contrôle) : *une infobulle que l'hôte ne
peut pas atteindre reste en anglais, partout*. Il développe les accesseurs de la
coquille et les boucles de l'hôte, puis exige que **chaque** zone de `TipText`
soit poussée. Il a d'abord dit NON sur deux zones réellement poussées — par un
indice littéral, une forme que mon motif ne lisait pas : **c'est l'instrument
qui a été corrigé, pas le contrôle qui a été désactivé.**

⚖️ **Ce que je n'ai PAS fait** : de contrôle automatique des accents. La sonde a
mesuré 26 candidats sur les 364 entrées ; **24 étaient des faux positifs de mon
propre dictionnaire** (« posiciones » et « operaciones » perdent leur accent au
pluriel, « verrouille » est ici un verbe). Un contrôle dont je ne peux pas
garantir le dictionnaire dirait NON à tort, et un gate qui crie au loup finit
par être ignoré. Les deux vrais écarts sont corrigés à la main.

**Gate : 21 contrôles, 0 en échec. Contrôles positifs : 19/19 + 2 non-couvertures
déclarées. Compilation : 0 erreur, 0 avertissement.**

### v3.56.68 — 5e lot : l'état, ce qui est chargé une fois et jamais rechargé

- 🔴 **Un aller-retour de phase effaçait le 2e strike, définitivement.**
  `ApplySettingsChange` — appelée à la fin de **chaque pas** de la cascade —
  remettait les deux drapeaux de violation à `false` dès que le profil courant
  ne peut pas être restreint. **Sans symétrique** : rien ne les rechargeait au
  retour, et ils n'étaient lus qu'à l'attache. Faire un clic sur le sélecteur de
  phase pour regarder ce que donnerait « Challenge P1 », puis revenir sur
  « Funded », suffisait. Le panneau affichait alors **3 % de plafond sur un
  compte qui en porte 1**, le conseiller de lot **triplait son budget**, et la
  case « Violation risque » se dessinait décochée **et active** : elle avait
  l'air d'être le reflet fidèle d'un état qu'elle contredisait. La variable
  globale, elle, valait toujours 1 — donc un simple changement d'unité de temps
  rebasculait au plafond de 1 %. **Deux réponses pour le même compte au même
  instant**, au gré du dernier événement de cycle de vie. Un seul chargeur
  désormais (`LoadViolationFlags`), appelé partout où le profil bouge ; une
  phase non restreignable **masque** les drapeaux, elle ne les détruit plus.
- 🔴 **Et le clic que l'écran refusait, l'hôte l'acceptait.** Le shell dessine
  ces deux cases désactivées dès que le profil ne peut pas être restreint —
  l'hôte, lui, prenait le clic et **écrivait** la violation dans la variable du
  compte. Le dégât était masqué par l'effacement ci-dessus ; la valeur stockée,
  elle, restait. Un contrôle dessiné refusé est maintenant refusé.
- 🔴 **Un changement de plan à chaud laissait la boîte à outils de risque sur
  OFF.** `g_eff_risktools` n'était résolu qu'à l'attache, alors que le plan est
  modifiable **à chaud** depuis la cascade. En passant de Personal à un plan
  prop en cours de session : **plus une seule alerte de règle**, plus de verrou
  discipline, plus de bandeau tilt — pendant que les jauges continuaient à
  peindre l'ambre et le rouge **exactement comme d'habitude**, donc sans que
  rien à l'écran ne dise que les alarmes étaient muettes. Et le retour arrière
  était impossible : sur un plan prop la bascule refuse le clic, sous une phrase
  qui affirme qu'elle est « toujours active », au-dessus d'un interrupteur
  dessiné OFF. La résolution est une fonction, rejouée à chaque changement.
- **La date de début de cycle pouvait être posée dans le FUTUR en un clic.** La
  *forme* était validée (jamais de 31 février) — la *position dans le temps*
  jamais. Et la valeur est persistée par login : elle survit au détachement, au
  changement d'unité de temps et au redémarrage. À partir de là,
  `HistorySelect(futur, maintenant)` rend un intervalle vide : **Quick Strike
  affiche 0,00 % sur un mètre vide et VERT** alors que le trader peut être
  au-delà du seuil de violation FN, et la carte news affiche 0 trade. Deux
  règles dont l'écran est le seul témoin passent de « surveillées » à
  « toujours propres », sans un message et sans un « n/a ». Plafonnée à
  aujourd'hui.
- **Dix globaux écrits et lus par personne.** Mesure faite **avant** de
  construire l'instrument : 89 globaux, **10 jamais relus**. `g_day_start` —
  une ancre de journée posée à minuit heure serveur à chaque attache, au milieu
  du bloc où se calcule **la règle la plus meurtrière du produit**, suggérant
  que la perte journalière est mesurée à partir de là et donc remise à zéro à
  chaque changement d'unité de temps. Elle ne l'est pas. Son jumeau avait déjà
  été retiré comme code mort ; celui-là avait survécu au nettoyage. Idem pour
  les trois restes de la surcouche plein écran et les trois anciennes boîtes de
  copie. Les **quatre miettes de diagnostic de la marge**, elles, ne sont pas
  supprimées : elles reprennent le rôle écrit dessus — une ligne verbeuse,
  limitée à une par minute, sur le **seul** chemin où le trader lit « n/a » sans
  raison. Elles coûtaient une concaténation de six morceaux à chaque appel pour
  un lecteur inexistant.

⭐ **Deux classes de défaut apprises par le gate** (20 contrôles) :
*un garde-fou doit garder quelque chose* — toute temporisation, constante ou
horodatage, doit apparaître dans une **comparaison** ; et *un état global doit
être relu* — un global écrit est, pour le compilateur, un global « utilisé ».
Les deux contrôles ont leur contrôle positif : on débranche, le gate dit NON.

**Gate : 20 contrôles, 0 en échec. Contrôles positifs : 18/18 + 2 non-couvertures
déclarées. Compilation : 0 erreur, 0 avertissement.**

### v3.55.67 — 4e lot : le chemin sonore, de bout en bout

Cinq constats de la revue, tous sur la meme fonction : **l'alarme**. Le panneau
sait depuis longtemps CALCULER le danger ; ce lot repare ce qu'il en DIT a voix
haute.

- 🔴 **Le limiteur d'alertes ne limitait rien.** Le fichier declarait, depuis
  toujours, un tableau d'horodatages avec son role ecrit dessus — *« 15-second
  cooldown per rule prevents spam on flapping transitions »*. Ce limiteur
  n'etait branche que sur le chemin Telegram, **mort depuis la v3.26**. Le son,
  lui, tournait sans bride : une regle qui respire autour de son seuil — un DD
  journalier a 870 $ pour une bande d'avertissement a 875 — faisait **alterner
  deux sons deux fois par seconde, sans fin**, exactement au moment ou la regle
  compte. Le compilateur ne voyait rien : la variable etait ecrite, donc
  « utilisee ». Elle garde desormais le SON, et la redescente gagne une
  **hysteresis** : on ne repasse en vert qu'a 5 % sous la bande, jamais des
  qu'on la frole. L'hysteresis ne joue que du **cote sur** — un outil de risque
  peut s'attarder en ambre, jamais en vert.
- **Plusieurs sons partaient a la suite, sans priorite.** Le declencheur jouait
  lui-meme, **a l'interieur de la boucle du registre**. Quand deux regles
  changeaient d'etat dans le meme rafraichissement, les sons s'enchainaient dans
  l'ordre du registre : **le son d'une BRECHE pouvait etre couvert par celui
  d'un simple avertissement declenche apres lui**. Le declencheur rend maintenant
  la GRAVITE de la transition, la boucle en garde le maximum, et **un seul son
  part**, le plus grave.
- 🔴 **Quick Strike avait deux seuils — et c'est moi qui les ai separes.** La
  v3.31 avait pose l'invariant *« une seule source pour le son et pour
  l'ecran »* ; la v3.39 a donne a l'**ecran** la bande du profil (avertir a
  20 %, violer a 25 %, soit 0,80 de la bande) en laissant le **son** sur le 0,80
  **generique**, calcule sur autre chose. Entre les deux valeurs, la ligne
  passait en ambre **et l'alarme se taisait**. La bande du profil vit desormais
  dans la fonction que les deux consommateurs lisent.
- **Le tilt et les verrous n'ont JAMAIS eu de son.** Le bloc d'en-tete de la
  section discipline promet *« a soft amber banner + sound »*, et la variable de
  temporisation porte *« tilt sound/Telegram throttle »* depuis le jour de sa
  declaration — mais **aucun `PlaySound` n'a jamais existe sur ce chemin**. Un
  bandeau ambre en haut d'un graphique qu'on ne regarde pas est un avertissement
  que personne ne recoit. Les deux transitions sonnent, sous la temporisation
  ecrite pour elles.
- 🔴 **L'alerte de tenue de week-end arrivait APRES la cloture.** Elle demandait
  d'aplatir a partir de **vendredi 22:00 UTC** — une heure **apres** la
  fermeture du forex, quand aplatir n'est plus possible. Un avertissement qui
  arrive apres l'echeance n'est pas un avertissement. Elle previent maintenant
  des **18:00 UTC** en ambre, de quoi travailler une sortie, et passe en
  **rouge a 20:30**, la derniere fenetre ou un ordre passe encore — avec son
  propre texte, et une annonce **par niveau** pour que l'escalade s'entende
  meme quand l'ambre a deja sonne.

⭐ **Le gate a appris la classe de defaut** (19e controle) : *un garde-fou doit
garder quelque chose*. Toute temporisation — constante `#define` ou horodatage
global — doit apparaitre dans une **comparaison**. Une variable ecrite mais
jamais confrontee a une horloge est une promesse non tenue, et le compilateur la
declare « utilisee ». Deux l'etaient dans ce seul fichier. Le controle positif
correspondant debranche la comparaison et verifie que le gate dit NON.

**Gate : 19 controles, 0 en echec. Controles positifs : 17/17 + 2 non-couvertures
declarees. Compilation : 0 erreur, 0 avertissement.**

### v3.52.64 -> v3.54.66 — 3e lot : deux chiffres impossibles, une carte volatile, une regression a moi

**v3.52 — deux chiffres qui ne pouvaient pas etre justes.**

- **Le compteur de jours minimum etait cable a ZERO.** `d.minDaysDone = 0;` avec
  le commentaire « filled by the strip logic when available » — la strip est le
  PANNEAU LEGACY, supprime en v3.06. `Live_TradingDaysCount()` existe, marche,
  est deja limitee a un balayage toutes les 30 s et est appelee ailleurs. Le
  panneau affichait donc **« 0 / 5 » en permanence** sur une regle FundedNext qui
  **bloque le retrait** : un compte pret a etre paye se montrait comme n'ayant
  jamais trade. **Cinq des quatorze dimensions l'ont trouve independamment.**
- 🔴 **Le pic de balance etait seme trop bas.** La graine etait
  `max(balance initiale, balance courante)`. Sur un compte deja trade qui est
  **monte puis redescendu**, le vrai pic est au-dessus de la balance courante —
  et le plancher glissant vaut `min(pic − permis, initial)`. Un pic sous-estime
  donne un plancher sous-estime, donc le panneau annonce **plus de marge de perte
  que le compte n'en a**. Le pic est desormais **reconstruit depuis
  l'historique** : on remonte a la balance de debut de cycle, on rejoue les
  mouvements dans l'ordre du temps, on garde le maximum. Une passe bornee, une
  seule fois, a l'initialisation, et le resultat ne peut que **relever** la
  graine.

**v3.53 — la carte des SL D'OUVERTURE vivait en memoire seule.** FundedNext
verrouille la regle des 3 % sur le stop pose **a l'ouverture**. Pour le savoir,
l'outil retient le premier stop non nul vu sur chaque ticket — dans un tableau
global MQL5 ordinaire, donc **remis a zero a chaque re-initialisation** :
changement d'unite de temps, de symbole, recompilation, redemarrage. Apres l'un
de ces gestes, le « premier » stop revu etait le stop COURANT. Un trader qui
avait remonte son stop voyait son risque verrouille **chuter**, alors que la
firme continue de noter le stop d'origine — encore la direction optimiste, et
depuis la v3.49 ce chiffre pilote aussi le score et l'alarme. La carte est
persistee par ticket **et par compte** dans les variables globales du terminal,
qui survivent au redemarrage, avec un ramassage des tickets fermes — y compris
ceux fermes pendant que l'outil etait arrete.

**v3.54 — trois defauts d'affichage, dont une regression que j'ai posee.**

- 🔴 **Les infobulles de la barre du haut etaient decalees d'un cran, et c'est MA
  faute.** La v3.27 a insere le bouton CADR dans l'enum des zones, entre MODE et
  CLOCK ; l'hote poussait ses textes **par indice**, de 0 a 8, sur une barre qui
  en compte desormais 10. Le bouton CADR portait le texte de l'**horloge**, et
  l'horloge portait **« Retirer : retire RiskCockpit de ce graphique »** — le
  libelle le plus dangereux de l'interface, pose sur le mauvais controle. Les
  textes sont remis en face, un dixieme est ajoute, et l'hote boucle desormais
  jusqu'a la **borne de l'enum**, pas jusqu'a un nombre ecrit a la main.
  ⭐ **Et le gate a appris cette classe** : il compare, pour chaque serie
  d'infobulles poussee par indice, le nombre de cles a la taille de la plage
  d'ids. Une insertion au milieu ne peut plus decaler la serie en silence.
- **La cellule POS du rail ignorait les lignes qu'elle pretend resumer.**
  `posWorst` regardait le nombre de positions, l'absence de stop et le garde-SL —
  jamais `posStat[]`, qui porte depuis la v3.35 le risque reel de chaque ligne.
  Lignes ambre, rail vert.
- **Le texte du bandeau d'alerte etait encre a partir du FOND DU THEME.** Sur un
  theme sombre cela donne du sombre sur un bandeau rouge, ce qui marche ; sur les
  **trois themes clairs**, le fond est clair donc l'encre est claire — texte pale
  sur bandeau ambre. Le message le plus urgent de l'interface etait le moins
  lisible. L'encre suit desormais la **luminance du bandeau**.

⚖️ **Un constat de la revue REFUTE par lecture** : « le plafond de marge cumulee
70 % de FundedNext est impose a FTMO / E8 / The5ers / Seacrest ». Faux — chacun de
ces profils pose `margin_max_cumulative_pct = 100.0`, ce qui rend le compteur
inactif, et le seul chemin qui pourrait l'ecraser est ferme sur un profil non
restreignable. Deuxieme constat ecarte apres verification, apres la fausse course
sur les steppers.

**Gate : 18 controles, 0 en echec. Self-test : 16/16 + 2 non-couvertures
declarees.**

### v3.50.62 / v3.51.63 — le GATE : six trous, deux plafonds silencieux, et un verdict plus large que la mesure

Deuxieme lot de la 3e revue. Cette fois la cible est **mon propre instrument**.

**Six trous dans `audit.py`, tous verifies par lecture avant correction :**

1. **L'exemption `articles/` etait une regle de PROXIMITE de 40 caracteres.** Elle
   blanchissait un vrai numero de compte des qu'une URL d'article FundedNext
   trainait n'importe ou dans les 40 caracteres precedents. Les chiffres doivent
   desormais SUIVRE `articles/` immediatement.
2. **Le scan de fuite etait une liste blanche d'EXTENSIONS.** Tout fichier sans
   extension — `LICENSE` en tete — n'etait jamais lu, pendant que le rapport
   annoncait « 12 fichiers scannes », ce qui se lit comme une couverture
   complete. Il lit maintenant **tout ce qui se decode en texte** (14 fichiers)
   et **DIT** combien de binaires il a ecartes.
3. **« binaire a jour » ne comparait que DEUX des six sources compilees.** Le
   catalogue des regles prop, les maths pures et le canevas pouvaient etre plus
   recents que le `.ex5` sans un mot. **Six sources comparees.**
4. **Le motif « login MT5 » ne voyait que 8 a 10 chiffres** : un login de 7
   chiffres passait. Et **« chemin local » exigeait des antislashs** : le meme
   chemin ecrit avec des barres obliques passait en clair.
5. 🔴 **Deux plafonds silencieux sur quatre n'etaient pas mesures.**
   `RCS_HELP_TOPICS` etait **SATURE a 10/10** : le prochain sujet d'aide aurait
   ete jete avec un `Print` que personne ne lit — le defaut de la v3.07, en plus
   discret. Et **`ZAdd` jetait SANS UN MOT** au-dela de 96 zones, seul des trois
   plafonds a ne pas avertir : une zone jetee est **un controle qui ne repond
   plus au clic**, sans erreur et sans trace. Manuel a 16, zones a **256** — au
   dessus du nombre total d'ids, donc aucune image ne peut plus deborder — et
   `ZAdd` le dit s'il devait quand meme refuser. Infobulles a 256 aussi : 170/192
   etait la meme marge fine.
6. 🔴 **AUCUN controle ne reliait `RC_VERSION_STR` a `#property version`.** C'est
   le defaut n°1 de la v3.17 : la section AIDE affichait une version que le
   binaire n'avait pas, donc un test portait sur un binaire qu'on croyait etre
   l'autre. Il est desormais impossible de les separer sans que le gate le dise.

**Et le self-test rendait un verdict sur 17 controles en n'en exercant que 9.**
Un controle qu'on n'a jamais fait echouer expres est une decoration. Le harnais
ne pouvait muter que le `.mq5` ; chaque cas porte maintenant **son** fichier
cible. **15 injections, 15 detectees**, et le harnais **imprime ce qu'il ne
couvre pas, avec la raison** — un self-test qui tait sa couverture ment de la
meme facon qu'un controle qui ne peut pas echouer.

⭐ **Le harnais renforce a trouve un trou de plus, tout seul** : le controle
« 3 langues par entree » ne verifiait que les entrees que son motif savait lire,
et se taisait sur les autres — **un verdict plus large que la mesure**, la meme
faute que le scan binaire d'avant la v3.41. Il compare desormais les entrees
ANALYSEES aux entrees PRESENTES. ⚠️ Et il a immediatement signale un faux
positif — la **definition** de `AddTr` comptee comme un appel — corrige dans la
foulee : c'est exactement ce qu'un controle neuf doit produire une fois, puis
plus jamais.

**Gate : 17 controles, 0 en echec. Self-test : 15/15, plus 2 non-couvertures
declarees.**

### v3.49.61 — premier lot de la 3e revue (180 agents, 73 constats confirmes)

Troisieme revue adversariale, demandee par JR : **14 dimensions** (securite,
surete du risque, regles FN, entrees non fiables, beaute, ergonomie, qualite du
code, robustesse MQL5, i18n, coherence des surfaces, etat et persistance, le gate
lui-meme, doc contre code, alertes), **au plus 6 constats chacune**, chacun
attaque par **deux angles independants** — un qui reproduit le chemin
d'execution ligne par ligne, un qui cherche a le refuter.
**180 agents, 22,3 M tokens, 83 constats bruts, 73 confirmes a l'unanimite.**
⚠️ Chaque constat est **reverifie a la main ici** avant d'etre touche : un
rapport d'agent est une donnee, pas un ordre.

🔴 **CRITIQUE — le drapeau « 2e strike RISQUE » par login etait ECRASE par la
variable globale lue juste apres.** Les deux drapeaux jumeaux n'etaient pas lus
dans le meme ordre : la marge lisait global PUIS par-login (le par-login gagne,
c'est correct) ; le risque lisait par-login PUIS global — **le global gagnait**,
et la lecture par login etait morte. Consequence : un trader qui decoche la case
sur un compte propre **efface la restriction de TOUS ses autres comptes**.
`EffectiveRiskCap()` rend alors 3 % au lieu de 1 %, et ce plafond alimente le
compteur LIMITES, le statut de chaque position, les lignes SL du graphique et
surtout **le budget du CONSEILLER DE LOT** : trois fois trop de risque conseille
sur un compte deja sous restriction, ou la prochaine violation est terminale.
Et le global n'etait pas la graine gelee que son propre commentaire decrit :
`PersistViolationFlags` le reecrivait a chaque clic, donc **le dernier compte
touche dictait la valeur de tous les autres** via le repli legacy. Les deux
lignes globales sont supprimees (`GVGetLogin` retombe deja sur la cle non
suffixee, aucune migration perdue) et la persistance n'ecrit plus que le par-login.

🔴 **Une bascule d'AFFICHAGE eteignait une REGLE.** `g_eff_news_high` est offerte
dans l'onglet AFFICHAGE comme un filtre — « quels niveaux d'impact tu veux voir
comptes » — et elle gardait les **quatre chemins de la REGLE** :
`Live_InNewsWindow`, `Live_NextNewsEvt`, `FFInNewsWindow`, `FFNextEvt`. La
decocher n'enlevait pas des marqueurs : elle **eteignait la regle des 40 %**, et
le panneau annoncait « aucune news » pendant un NFP. Un reglage d'affichage ne
doit JAMAIS pouvoir desactiver une regle. Elle ne filtre plus que ce qui est
DESSINE.

🔴 **Le chiffre que la firme NOTE ne pilotait rien.** La v3.35 a mis le risque
VERROUILLE a l'ecran — le risque au stop pose A L'OUVERTURE, celui que
FundedNext score — et l'a laisse **hors de l'agregat** : ni le score, ni la jauge
du rail, ni le verdict, ni l'alarme ne le voyaient. Le panneau pouvait afficher
3,1 % de risque verrouille **en restant vert**. Il entre dans l'agregat, avec le
seuil de la regle de risque.

**Un calendrier MUET etait rendu comme « aucune news ».** `CalendarValueHistory`
qui echoue faisait rendre `false` a la fenetre et `0` au prochain evenement : le
panneau affichait « Rien dans les 24 h » avec la meme serenite que s'il avait
verifie. La source MT5 etait **la seule sans detection de panne** — le pont
ForexFactory en a une depuis la v3.26. Elle dit maintenant « SOURCE ILLISIBLE ».

### v3.47.59 / v3.48.60 — deux chemins morts retires, et la news qui se contredisait

**v3.47 — du code mort dans un depot PUBLIC.**

- **La puce « SL > recommande » ecrivait dans un panneau detruit.** Quand le stop
  de l'utilisateur est PLUS LARGE que le stop conseille, la ligne du graphique
  est tracee en rouge avec le suffixe OVER — cette partie est vivante et utile.
  Mais le meme bloc ecrivait aussi dans `g_pos_status[]`, un tableau que plus
  rien ne lit, et dans un objet du panneau **supprime en v3.06**. Les deux
  ecritures ne faisaient rien depuis. Et l'information n'est plus absente :
  **depuis la v3.35** une position dont le risque depasse le budget par trade
  passe deja sa ligne en ambre, calculee sur le risque lui-meme.
- 🔴 **Le bloc d'alerte Telegram composait le NUMERO DE COMPTE.** Il etait garde
  par `if (false && ...)` et l'envoyeur retournait `false` des sa premiere ligne
  depuis la v3.26 — mais **inatteignable n'est pas absent**. C'est un depot
  PUBLIC, et un chemin dormant qui formate un numero de compte dans un message
  sortant n'a rien a y faire. Le bloc est retire, l'envoyeur devient un stub de
  deux lignes qui dit pourquoi, et quarante lignes de HTTP disparaissent. La
  bascule reste, dessinee verrouillee avec sa raison : le reglage est reel, la
  version EA s'en sert, et un indicateur ne peut simplement pas envoyer.

**v3.48 — l'ETAT news et le COMPTE A REBOURS news repondaient a deux questions
differentes.** Sous calendrier MT5 :

- `Live_InNewsWindow()` filtrait par devise, et **naivement** :
  `currency == base || currency == quote`.
- `Live_NextNewsEvt()` n'avait **AUCUN filtre de devise** — deliberement, et le
  commentaire disait pourquoi : le test base/quote **cassait sur les indices**
  (la base et la cotation de US30 ne sont pas les devises sous lesquelles ses
  news sont classees), donc la ligne « ne se remplissait jamais ».

Resultat : le panneau pouvait decompter jusqu'a un evenement — « dans 12 min » —
et **en meme temps declarer la fenetre « inactive » une fois dedans**, parce que
l'evenement echouait a un filtre que le compte a rebours n'appliquait pas.
**Deux surfaces, une question, deux reponses.**

Le chemin ForexFactory n'a jamais eu ce probleme : il utilise
`NewsCcyAffectsSymbol()`, qui sait que US30 et NAS vivent sur les news USD, que
l'or est classe sous USD, AUD et CAD, etc. **C'est exactement ce qui manquait au
test base/quote — donc la raison d'avoir supprime le filtre a disparu.** Les
trois balayages MT5 utilisent desormais ce meme matcher : l'etat et le compte a
rebours repondent a la meme question sur le meme symbole, et les indices et
metaux fonctionnent — ce que la suppression du filtre cherchait a obtenir.

Les marqueurs sur le graphique continuent d'afficher toutes les devises : cette
surface est un apercu du calendrier, pas une affirmation sur la regle de CE
symbole.

### v3.44.56 -> v3.46.58 — la section AIDE devient le MANUEL

JR : « dans la partie aide ajoute pour chaque menu et partie un onglet
coulissant que tu ouvres et fermes, et ajoute tous les elements avec une
description, pour aider les gens a utiliser l'app. Et aussi ajoute un guide
d'utilisation. »

**Dix volets depliables** : un **GUIDE D'UTILISATION** en huit etapes d'abord,
puis un volet par surface (barre du haut, rail, tableau flottant) et un par
section (limites, lot, news, discipline, compte, reglages) — **78 elements**,
chacun avec ce qu'il veut dire, en **EN / FR / ES**.

Les volets sont **EXCLUSIFS** : en ouvrir un referme les autres. Un manuel
capable de deplier dix sujets a la fois deborderait n'importe quel graphique, et
la seule chose que ce panneau ne doit plus jamais faire, c'est perdre son bas
sans le dire.

Le catalogue est pousse par l'**HOTE**, une fois, depuis `ShellPushLabels` :
meme contrat que les libelles et les infobulles, donc **une seule table de
traduction** sert tout le produit et un changement de langue repousse tout.
Chaque ligne est empaquetee `libelle|description`, la convention que `SetTip`
utilise deja.

**v3.45 — les vrais accents.** Le catalogue v3.44 avait ete ecrit **sans
accents** pour contourner des ennuis d'echappement dans mon outillage de patch —
c'est mon probleme, pas celui du lecteur. Un manuel qui dit « Regler ton plan /
cote / apres » a l'air inacheve. Bloc entier regenere : memes cles, meme ordre,
anglais inchange, **francais et espagnol accentues** (regle JR du 04/09).

**v3.46 — le manuel ne commence plus une ligne par deux-points.** Le francais
met une espace AVANT `:` `;` `!` `?`, donc un algorithme qui coupe sur n'importe
quelle espace ouvre volontiers une ligne par un `:` — vu a l'ecran (« quelque
chose cloche » / « : marge libre sous le minimum »). Le point de coupe refuse
desormais une espace suivie d'une ponctuation qui ne peut pas ouvrir une ligne.

### v3.42.54 / v3.43.55 — le GLITCH news : un champ ajoute a l'instantane et a aucune des deux copies

JR : « il y a un probleme de chargement sur la partie news et ca glitche entre FF
et MT5 et c'est comme si ca recharge toutes les 2 secondes ».

Le bloc news est calcule une fois puis **servi depuis un cache pendant 15 s** :
la branche fraiche remplit les champs, la branche cachee les recopie depuis
`s_newsCache`, et une reecriture les y remet. La v3.37 a ajoute `d.newsApplies`
**a la branche fraiche et a AUCUNE des deux copies.**

`d` est un local **remis a zero a chaque appel**. Donc :
- **une image sur ~30** : `newsApplies` a sa vraie valeur ;
- **toutes les autres** : `newsApplies` = false.

Sur un profil ou la regle s'applique (**financé**), la section news, le titre de
la legende et la pastille du rail basculaient donc entre « la regle et sa
source » et « aucune regle news sur ce profil », **deux fois par seconde**. Et
comme la **hauteur** de la section differe entre ces deux etats, le panneau se
re-mesurait et **re-creait toutes ses surfaces a presque chaque image** — c'est
la partie « ca recharge ».

**Deux correctifs, et le second est celui qui compte :**

1. `newsApplies` **sort du bloc cache**. C'est `g_profile.news_rule_applies`, un
   champ de structure, **gratuit a lire**. Une valeur qui ne coute rien ne doit
   jamais vivre derriere un cache : ca n'achete aucun temps et ca cree une facon
   de se tromper.
2. ⭐ **LE GATE APPREND CETTE CLASSE DE DEFAUT.** Un instantane est un
   **contrat** : tout champ que la branche fraiche remplit doit etre lisible
   depuis le cache **et** inscriptible dedans. Le compilateur n'en voit rien —
   le champ existe, ca compile, et la valeur est simplement fausse cinq images
   sur six. `audit.py` compare desormais les trois listes.
   ⭐ **Le controle a attrape le defaut VIVANT avant sa correction** — il a dit
   NON sur un vrai defaut, ce qui est la seule preuve qu'un instrument sait dire
   non. Et l'injection ajoutee au self-test retire un champ de la reecriture :
   **9 injections sur 9 detectees.**

**Prouve a l'ecran** : profil bascule sur FundedNext / Stellar 1-Step /
**Funded** (la ou la regle s'applique), section news ouverte, **14 images
consecutives identiques** — source ForexFactory [FF], etat, fenetre, A VENIR.
Le profil personnel de JR a ensuite ete **remis a l'identique**.

**v3.43 — une infobulle qui ne partait jamais.** Une infobulle est cachee par
`OnMouseMove`, quand le curseur entre dans une autre zone ou quitte toutes les
zones. Mais des que le curseur quitte **la fenetre du graphique**, MT5 cesse
d'envoyer le moindre evenement de souris : la derniere infobulle **restait
peinte par-dessus les lignes du dessous**, aussi longtemps que le curseur etait
ailleurs sur l'ecran. Vu en travaillant : une infobulle « Compte » posee sur les
lignes du compte, et une infobulle « News » **recouvrant la ligne Source** — ce
qui, vu de l'exterieur, ressemble exactement a « ca glitche entre FF et MT5 » :
la valeur est la, une boite la cache, elle revient. Une infobulle est une aide,
pas un etat : elle **expire toute seule au bout de 6 secondes**.

### v3.41.53 — le drawdown JOURNALIER etait reconstruit sur une somme incomplete

`Live_DailyDdPct` reconstruit le solde de debut de journee comme
`solde_actuel - realise_du_jour`, et `realise_du_jour` ne comptait que
`DEAL_ENTRY_OUT` et `DEAL_ENTRY_INOUT`. Deux choses passaient au travers :

1. **`DEAL_ENTRY_OUT_BY`** — la cloture « close by », une position fermee CONTRE
   une position opposee. L'outil tourne sur des comptes **hedge**, ou c'est une
   facon ordinaire de se mettre a plat : son P&L disparaissait simplement de la
   journee.
2. 🔴 **Toute operation de SOLDE** — depot, **retrait**, credit, correction,
   bonus. Elles deplacent `ACCOUNT_BALANCE` sans produire le moindre P&L de
   trading, donc la soustraction ci-dessus est fausse **du montant exact
   deplace**. Un retrait rendait le solde de debut de journee reconstruit trop
   HAUT, et le panneau annoncait **un drawdown journalier qui n'avait pas eu
   lieu** — potentiellement une breche un jour sans un seul trade perdant.

Le premier rejoint la somme des P&L ; les operations de solde sont soustraites
**a part**, parce qu'elles ne sont pas du P&L et ne doivent jamais etre comptees
comme telles. Meme fenetre, meme cadence de 2 s : une passe bornee, jamais a
chaque tick.

**Et le gate affirmait plus qu'il ne prouve.** Son controle positif du scan
binaire cherche la chaine `#property link` — or les `#property` sont stockees
**NON COMPRESSEES** en UTF-16LE dans l'**en-tete** du `.ex5`, tandis que les
chaines du corps sont compressees. Le controle prouvait donc qu'on sait lire
**0,3 %** du fichier, et rien sur les 99,7 % ou une chaine fuitee vivrait
vraiment — puis le rapport disait « 12 fichiers + binaire scannes », ce qui se
lit « le binaire est propre ». **Ce n'est pas un verdict, c'est l'absence de
verdict.** Le controle est desormais scinde : les **sources** portent le verdict
(texte clair, aucun octet ne se cache), le **binaire** est rapporte a part et
etiquete pour ce qu'il couvre — « en-tete lisible, corps COMPRESSE donc NON
couvert ». 13 controles au lieu de 12.

### v3.37.49 -> v3.40.52 — la regle news : a qui elle s'applique, et ce qu'un jeton inconnu veut dire

🔴 **ECHEC OUVERT SUR UNE ENTREE NON FIABLE.** `NewsCcyAffectsSymbol()` rendait
**faux** pour tout code devise qu'elle ne reconnaissait pas, et `FFInNewsWindow`
ignorait ces evenements. Or `country` vient d'un fichier JSON que l'indicateur ne
controle pas : une valeur corrompue, renommee ou falsifiee **eteignait
silencieusement toute la regle news pendant les minutes exactes pour lesquelles
elle existe**. Un outil de risque doit echouer du cote SUR : un jeton qui n'est
pas une devise dont on sait raisonner **COMPTE** desormais. Un faux « tu es dans
une fenetre news » coute un trade manque ; un faux « tu es tranquille » coute le
compte.

**Le chemin ForexFactory ignorait `news_rule_applies`.** Les trois chemins du
calendrier MT5 le verifiaient tous ; `FFInNewsWindow` non. Sur un profil ou
FundedNext n'applique pas la regle, **basculer sur le flux ForexFactory la
ramenait a la vie**. Et le panneau l'affichait quand meme : une source, un etat,
une fenetre et un compte a rebours **pour une regle inventee pour le lecteur**.
Il dit maintenant N/A, une fois. La v3.40 aligne la page LEGENDE, qui continuait
d'expliquer quelle part du profit compte sur un compte ou rien ne compte : deux
surfaces, un fait, deux reponses — le lecteur croit celle qu'il a vue en dernier.

**v3.38 — deux entrees non fiables, et un README qui promettait ce que le code
refusait.**
- 🔴 **Le pic de balance est une GlobalVariable NON AUTHENTIFIEE.** C'est le
  point haut dont depend le plancher glissant : `plancher = min(pic − permis,
  initial)`. N'importe quel script, n'importe quel EA, une edition a la main dans
  la fenetre des variables globales du terminal peut **l'abaisser** — et un pic
  plus bas que la realite **abaisse le plancher**, donc le panneau annonce **PLUS
  de marge de perte** que le compte n'en a. C'est la seule direction dans
  laquelle un outil de risque n'a pas le droit de se tromper. La valeur restauree
  est desormais bornee par ce que le terminal observe tout seul.
- `FFJsonStr` **bornait sa recherche APRES l'avoir faite** : une cle absente d'un
  evenement coutait un balayage de tout le reste du fichier, une fois par champ
  manquant — sur un fichier que l'indicateur ne controle pas, c'est l'entree qui
  choisit la charge du thread d'interface.
- Le **README promettait un auto-verrou « you cannot undo before it expires »**.
  Le code a toujours eu un relachement (deux clics en 5 s), **volontairement** :
  un pacte dont on ne peut pas sortir est un piege. Le README dit desormais ce
  que le code fait, et gagne l'echelle de verrous restauree en v3.33.

**v3.39 — deux nombres que le profil connaissait et que le panneau aplatissait.**
- **Quick Strike** avait perdu sa propre bande d'alerte : le catalogue porte
  `quick_strike_warn_pct` et `quick_strike_violate_pct`, et l'ancienne ligne
  avertissait sur leur RATIO. La v3.31 a rendu son seuil a chaque regle, mais
  Quick Strike recevait le 0,80 generique. Sa bande est reprise du profil.
- **« NO SL » etait une etiquette figee.** FundedNext donne **trois minutes** pour
  poser un stop — le code le dit la ou il calcule le risque — et le panneau
  affichait le meme rouge a la seconde 2 et a la minute 40. La ligne decompte
  desormais le sursis, en ambre tant qu'il dure et en rouge une fois passe :
  c'est la difference entre « pose ton stop » et « tu es deja en violation ».

### v3.33.45 -> v3.36.48 — la DISCIPLINE etait declaree et n'etait plus nourrie

🔴 **Le moteur de discipline ne tournait plus du tout.** `g_disc_consec`,
`g_disc_lastloss`, `g_disc_trades_win` et `g_disc_revenge` etaient **declares**,
**lus** par le modele du panneau, et ecrits par **RIEN** :
`ComputeDisciplineMetrics()` — l'unique balayage d'historique qui les
remplissait — est parti avec l'ancien panneau en v3.06 et n'a jamais ete
remplace. Consequences, toutes silencieuses :

- **Le TILT ne partait jamais.** Le bandeau ambre et son son etaient morts, et le
  panneau affichait « Fenetre tilt : 0 en 5 min (max 5) » — **un compteur qui ne
  pouvait pas bouger**.
- **La PAUSE apres N pertes consecutives n'existait pas du tout.** Le reglage
  etait toujours la, toujours persiste, toujours reglable — et ne commandait
  rien. C'est pire que pas de reglage.
- **Le verrou dur sur le drawdown journalier (>= 80 % du plafond) avait disparu.**
  Seul l'auto-verrou pouvait encore verrouiller.
- **La bascule maitresse « Verrou discipline » ne commandait donc rien** : elle
  gardait un tilt qui ne pouvait pas partir et un verrou qui n'existait plus.

Et le bloc de commentaires au-dessus de l'etat **decrivait toujours l'echelle
complete, dans l'ordre**. Le code n'en faisait rien. Pour un outil de discipline,
une regle qui cesse silencieusement de s'appliquer est pire qu'une regle jamais
promise. Le balayage est celui de l'ancien build (borne, cache 5 s, hors du
chemin des 500 ms) ; l'echelle est celle de l'ancien build ; **seul le rendu
change** — il alimente le bandeau de securite v3 au lieu de l'overlay supprime.

**v3.34 — ce qu'un verrou doit reellement empecher.**
- **RELACHER etait propose pour TOUS les verrous.** Depuis la v3.33 trois verrous
  peuvent tenir : l'auto-verrou (le pacte du trader — relachable en deux clics,
  sinon c'est un piege), le verrou de drawdown journalier et la pause apres une
  serie de pertes. Les deux derniers sont des **REGLES**, pas des pactes :
  offrir deux clics pour les congedier transformait la regle en suggestion.
- **Un verrou dur laissait toutes les portes de sortie ouvertes.** Le bandeau
  disait « VERROU DISCIPLINE ACTIF » pendant que la croix de la navbar retirait
  encore l'outil du graphique et que **chaque reglage de risque pouvait encore
  etre desserre**. Ce n'est pas un verrou, c'est une etiquette. Le shell avale
  desormais les clics qui mettraient fin au verrou ou le desserreraient, garde
  vivant tout ce qui ne fait que LIRE, et **dit** que le clic a ete refuse.
- **`PersistViolationFlags()` existait, etait declaree, et n'etait appelee par
  RIEN.** Les deux bascules de violation n'ecrivaient que la variable GLOBALE,
  jamais la copie par login que le chargeur lit en premier : le drapeau fuyait
  d'un compte a l'autre et n'etait jamais enregistre la ou on le cherche.

**v3.35 — quatre choses que le code savait deja et ne disait pas.**
- 🔴 **Le chiffre que FundedNext NOTE reellement n'etait pas a l'ecran.**
  `Live_LockedRiskPct()` est definie, documentee, et appelee par **RIEN**. FN
  verrouille la regle des 3 % de risque ouvert sur le stop pose **A
  L'OUVERTURE** — deplacer le stop ensuite ne change pas ce qu'ils notent
  (leur mail du 29/05/2026). Le panneau n'affichait que le risque cumule VIVANT,
  qui baisse des qu'on suit le stop : **il pouvait afficher 1,2 % pendant que la
  firme notait 3,1 %.** Les deux chiffres sont desormais cote a cote.
- **Le statut d'une ligne de position suivait le SIGNE de son P&L.** Vert quand
  ca monte, ambre quand ca descend — ce n'est pas une regle, c'est une humeur.
  Une perte dans son risque prevu est normale ; **un trade GAGNANT qui porte tout
  le budget est celui qui met fin au compte.** Le statut est desormais le risque
  propre de la position face au budget par trade (plafond / N).
- **Le conseiller de lot jetait ses drapeaux.** `below_min`, `over_budget`,
  `margin_bound`, `margin_insufficient`, `reduce_flag` : tous calcules, aucun
  transporte. Le panneau donnait un lot sans jamais pouvoir dire « votre marge
  libre ne couvre meme pas le lot minimum du courtier ».
- **Le rail pouvait s'ancrer HORS ECRAN.** Le plancher de 400 px sert aux
  decisions de mise en page ; il atteignait l'ANCRE, donc sur un graphique plus
  etroit le rail — **la seule surface permanente, celle qui ouvre tout le
  reste** — etait place en dehors de la zone visible.
- Et la **palette** : le shell demarrait toujours sur `InpPalette` alors que la
  palette choisie par l'utilisateur, deja restauree, se trouvait deux lignes plus
  haut.

**v3.36** — 156 libelles pousses pour 155 demandes : `RCL_LOSSES` avait ete cree
et jamais utilise. Il porte maintenant le nombre de pertes d'affilee qui a
declenche la pause (« 12 min restantes » dit quand, jamais pourquoi). Et le
plafond des libelles passe de 192 a **256** : 184 ids pour 192 slots, c'est
exactement ainsi que revient le defaut de la v3.07, ou des ids etaient
silencieusement jetes.

### v3.31.43 / v3.32.44 — l'alarme et l'ecran disent enfin la meme chose

Premier lot de la revue de PARITE (66 agents contre l'ancien panneau
`v3.05.16`, 8803 lignes). Chaque constat a ete **reverifie ligne par ligne** ici
avant d'etre touche.

🔴 **Le seuil qui SONNE et le seuil qui COLORE n'etaient pas le meme nombre.**
Le son utilisait un seuil **par regle** — 70 % pour le risque cumule et le DD
journalier, **50 %** pour un DD total TRAILING (la regle qui tue le compte),
75 % pour l'hyperactivite et les messages serveur — pendant que **cinq surfaces**
comparaient les memes ratios a un **0,80 en dur**. Un DD journalier a 3,6 % d'un
plafond de 5 % vaut 0,72 : **l'alarme part, la barre reste VERTE**. Sur un
Instant, un DD total a 3,1 % de 6 % vaut 0,517 : l'alarme part a 0,50, la barre
reste verte jusqu'a 4,8 % — **trente points d'ecart sur la regle qui met fin au
compte**. Le trader entend une alarme, regarde un panneau qui dit que tout va
bien, et conclut que l'alarme est un faux positif. Pire que l'un ou l'autre
comportement pris seul.

Et le chiffre corrige **n'avait aucun porte-voix** : `g_rows[i].status`, seul
porteur des 0,70 / 0,50 / 0,75, n'etait lu que par le son et par un bloc Telegram
mort (`if (false && ...)`). Le correctif v3.17 vivait entierement **hors du champ
visuel**. Desormais **une** fonction decide, `RuleWarnRatio()`, et elle alimente
le son ET le modele que le shell peint. Le repere de la jauge se place sur le
seuil qui s'applique vraiment, et son infobulle cesse d'affirmer « Marqueur =
80 % ».

🔴 **Le score de sante comptait QUATRE regles sur les SEPT qui peuvent partir.**
Quick Strike, hyperactivite et messages serveur n'entraient pas dans l'agregat :
**100/100 restait atteignable avec le compteur d'hyperactivite a son plafond.**
Les sept comptent. ⚠️ Mon premier correctif repliait ces trois regles **cent
lignes avant** que leurs champs soient remplis — elles auraient compte pour zero,
exactement le defaut a corriger. L'agregat **ouvre** sur les quatre limites et
**ferme** la ou chaque regle a ses chiffres.

⭐ **Le self-test a ete EXECUTE pour la premiere fois** (il existait depuis la
v3.16 sans avoir jamais tourne) : **37 PASS, 0 FAIL**, dont six cas neufs qui
verrouillent exactement le defaut ci-dessus — 72 % d'un plafond a seuil 70 %
avertit, 72 % d'un plafond a seuil 80 % **n'avertit pas**. `#property
script_show_inputs` a ete retire : il ne montrait aucun input, il ne mettait
qu'une boite de dialogue entre l'utilisateur et le resultat.

**v3.32** — la ligne de troncature repondait a la mauvaise question. Une sonde
posee dans le rendu a montre le cas reel : `H=860`, huit en-tetes dessines,
curseur a `y=1047` — **187 px de la derniere section peints hors du bitmap**, et
la ligne muette parce que `shown == 8`. Elle demandait « est-ce qu'un EN-TETE
manque » alors que la question est « est-ce qu'un CONTENU est coupe ». Elle part
sur les deux, sur un bandeau qui la garde lisible.

### v3.27.39 -> v3.30.42 — le panneau complet devient un ACCORDEON, et la barre du haut porte les chiffres

JR, apres avoir vu la v3.26 tourner : « on perd le bas du menu », « les infos
importantes sur la barre horizontale du haut », « un bouton pour centrer le chart
a cote du theme ». Il a laisse le choix de la solution pour le premier point,
entre montrer moins, faire defiler, ou plier les sections.

**1. Le panneau complet est un ACCORDEON.** Il empilait huit sections a la
suite : les dernieres tombaient hors du graphique et rien ne le disait — la
ligne d'honnetete elle-meme etait peinte au curseur `y`, donc hors du bitmap.
Chaque section garde desormais un **en-tete cliquable** ; seuls les **corps** se
plient. Rien n'est cache : ce qui ne rentre pas est a un clic. L'etat est
**persiste par login**, avec l'etat du panneau (ouvert / quelle section / plein)
— avant, chaque changement d'unite de temps refermait tout, et un outil qu'il
faut rouvrir est un outil qu'on cesse d'ouvrir.

⚠️ **Deux defauts de mon propre accordeon, trouves a l'ecran, pas au compilateur :**
- Le panneau **OSCILLAIT** entre deux hauteurs. La boucle reservait 46 px avant
  d'ouvrir une section, mais la mesure demandait `y + 14` : haut, tout rentre et
  la mesure demande a RETRECIR ; bas, le dernier en-tete ne rentre plus et elle
  demande a GRANDIR. Deux hauteurs, indefiniment, **une reconstruction complete
  des surfaces a chaque frame**. La mesure ne fait plus que GRANDIR, et elle est
  remise a zero au repli d'une section — le seul moment ou la pile peut
  legitimement raccourcir.
- **Titres en double** : l'en-tete disait « POSITIONS OUVERTES » et le corps le
  repetait mot pour mot juste en dessous. Le premier titre d'un corps est
  supprime **uniquement** s'il repete l'en-tete a l'identique, donc un corps dont
  le premier titre dit autre chose (« ETAT », « CONSOMMATION DES LIMITES ») le
  garde.

**2. La barre du haut porte les trois chiffres qui decident du clic suivant** —
marge jusqu'a la limite la plus proche, lot conseille, prochaine news — colores
par leur propre etat, puis l'equite et le nombre de positions. Elle repond
« est-ce que je peux prendre ce trade » sans rien ouvrir. Barre elargie de 750 a
980 px, avec degradation progressive : sur un graphique etroit les chips tombent
une par une, jamais de debordement.

**3. Bouton CADR (FIT)**, entre la palette et le D/L : il **arme** l'echelle
confort et re-cadre immediatement. Un bouton qui n'agirait que si un reglage est
deja actif est un piege — il allume le reglage lui-meme.

### v3.26.38 — passe de SECURITE

Revue adversariale a 53 agents (fuite de donnees, garantie lecture seule,
parsing de donnees non fiables, systeme de fichiers, interference entre
indicateurs, ressources, distribution). Chaque constat a ete **reverifie dans le
code** avant d'etre touche : un rapport d'agent est une donnee, pas un ordre.

**Fuite reelle, dans le depot PUBLIC.** `HISTORY.md` portait un vrai numero de
compte MT5 (demo, mais la regle est **zero**). Il est masque. Le controle du gate
**ne pouvait pas le voir** : son motif exigeait le mot « compte »/« login » a
moins de 3 caracteres des chiffres, et la ligne disait « compte **demo** Ava,
<numero> » — quatorze caracteres plus loin. C'est la **deuxieme fois** que ce
controle rend OK sur le fichier qui porte la fuite. Il signale desormais **toute
suite de 8 a 10 chiffres** hors d'une liste blanche explicite (ids d'articles
FundedNext, une date), et le binaire recoit la meme regle. L'injection du
self-test a ete refaite dans la forme qui passait : `8/8` detectes.
⚠️ **Deux messages de commit deja pousses portent encore un numero de compte.**
Un fichier se corrige, un message de commit demande une **reecriture d'historique
public** : c'est la decision de JR, pas la mienne.

**Le jeton Telegram etait un `input string` en clair.** MQL5 **interdit**
`WebRequest` dans un indicateur : ce build ne peut donc **jamais** envoyer un
message — pendant que MT5 recopie chaque `input` dans des `.set` et des modeles
de graphique qu'aucun garde-fou ne scanne. Un reglage qui ne peut pas servir et
ne peut que fuir n'a pas lieu d'exister : les deux entrees sont retirees.

**Le solde de POINTE du compte partait dans le journal Experts** a chaque
session, sans condition — et un journal Experts est ce qu'un trader colle dans un
fil de support. Passe derriere `InpVerboseLog`.

**Une bascule dessinee VERROUILLEE restait cliquable** : `ZAdd` etait appele meme
quand `locked` etait vrai. Les deux bascules « apres violation » resserraient
donc reellement les plafonds tout en affirmant au lecteur qu'elles ne pouvaient
rien. Un controle qui ne peut pas agir ne doit pas etre cliquable.

**Le calendrier ForexFactory etait charge UNE fois et jamais relu**
(`if (ArraySize(g_ff_events) == 0)`). Un terminal laisse ouvert un week-end
gardait les evenements de la semaine precedente pendant que le service
compagnon reecrivait le fichier toutes les heures. Tout etant passe, le panneau
annoncait « rien dans les 24 h » **badge [FF] allume**, et `g_ff_active`, jamais
remis a false, gardait le calendrier MT5 hors-jeu : **les deux filets tombaient
ensemble**. Desormais : relecture des que la date de modification bouge, et un
cache sans aucun evenement courant ou futur est traite comme une **PANNE de
source** (badge eteint, la regle news repart sur le calendrier MT5), jamais comme
« pas de news ».

**Entrees non fiables bornees.** Aucun plafond n'existait sur le nombre
d'evenements analyses : un fichier de 4 Mo allouait sans limite, puis payait un
tri O(n2) et un objet graphique par evenement **a chaque rafraichissement**
(plafond 512). Et `FFParseIso8601Utc` ne validait que la date : l'heure, la
minute, la seconde, la borne haute de l'annee et le decalage horaire passaient
tels quels — un decalage aberrant deplacait un evenement de plusieurs jours.

### v3.24.36 / v3.25.37 — quatre defauts vus a l'ecran par JR

**1. Les boites « copier » disparaissaient des qu'on bougeait le graphique.**
La v3.24 accusait `Destroy()` / `ObjectsDeleteAll`. **Ce diagnostic etait FAUX** :
`OnChartChange()` n'appelle jamais `ObjectsDeleteAll`, et le timer re-synchronise
les boites deux fois par seconde. Les boites ne sont jamais supprimees, elles sont
**RECOUVERTES** : MT5 peint les objets d'un graphique dans l'**ordre de creation**
(`OBJPROP_ZORDER` ne classe que les clics), donc un bitmap de panneau re-cree passe
devant un `OBJ_EDIT` plus ancien. `ShellSyncLotEdit` trouvait l'objet et se
contentait de le DEPLACER — il restait dessous pour toujours. Le shell compte
desormais ses generations de surfaces (`SurfGen()`) et l'hote supprime les deux
boites apres chaque reconstruction, pour que la synchro suivante les re-cree
au-dessus. **Prouve a l'ecran** : 8 barres de defilement, deux zooms, PgUp/PgDn —
les deux boites (`0.01` et `0.75`) restent presentes.

**2. Le panneau COMPLET etait haut de 740 px en dur.** La pile de sections
debordait : « A VENIR » etait le dernier titre dessine et son contenu tombait
hors du bitmap. Le panneau **mesure** maintenant sa pile et grandit jusqu'a la
hauteur du graphique. Mesure a l'ecran : 730 px -> **990 px**, et « A VENIR »
affiche enfin sa ligne (« Rien dans les 24 h. »). La ligne d'honnetete
« +N sections : agrandir la fenetre » etait elle-meme peinte AU curseur `y`,
c'est-a-dire exactement la ou le bitmap se termine : la seule ligne chargee de
dire « il y a la suite » n'etait jamais visible. Elle est desormais peinte a
position fixe, en bas du panneau.

**3. L'echelle confort avait une bascule a sens unique.** La rallumer appelait
`ApplyComfortScale(false)`, qui **refuse** d'agir sur une echelle fixe qui n'est
pas la notre : le clic ne faisait donc **rien**. L'eteindre ne rendait pas non
plus le graphique, fige sur notre propre echelle. ON force maintenant ; OFF rend
l'echelle native, mais seulement si elle est encore la notre (jamais de zoom
manuel ecrase). Trouve a l'ecran : la bascule etait persistee sur OFF, ce qui
explique le graphique colle en haut et en bas dont JR se plaignait.

**4. La section COMPTE portait le plan, pas le COMPTE.** Ni courtier, ni serveur,
ni levier, ni equite, ni marge — l'ancien onglet « Compte » les avait. Bloc
TERMINAL ajoute, en lecture seule : courtier, serveur, levier, solde, equite,
marge utilisee, marge libre.

### v3.22.34 / v3.23.35 — première vérification À L'ÉCRAN

JR a autorisé l'ouverture de son terminal (un compte **démo** Ava).
L'indicateur a été attaché à EURUSD M15 et piloté à la souris : c'est la
première fois que ce shell est **vu tourner**.

**Ce qui marche, vérifié à l'image** — navbar complète (`RC | EURUSD | M15 |
SAIN 100/100 | $10174.11 | 0 pos | EMER | D | 00:33 | ✕`), rail collé au bord
avec ses 8 cellules et leurs micro-états, tableau flottant en **état vide**
(« Aucune position ouverte », bandeau d'accès rapide, mention « Fermeture :
version EA »), sidebar complète empilant toutes les sections, infobulle sur
**2 lignes** (correctif v3.20), sections repliées/dépliées au clic, tableau des
réglages avec ses 4 onglets et ses 6 steppers, `N/A` honnête là où une limite
ne s'applique pas au profil personnel.

**Chaîne fonctionnelle prouvée de bout en bout** : deux clics sur le `+` de
« Distance SL % » → `1.00 %` devient `1.20 %`, deux clics sur `−` la ramènent à
`1.00 %`. Les **deux** clics comptent, ce qui valide aussi le correctif v3.19
(avant, deux clics dans une même période de rafraîchissement n'en faisaient
qu'un). Clic → zone → intention → hôte → mutation → GlobalVariable → re-rendu.

**Trois défauts que quinze contrôles statiques n'ont pas pu voir :**

1. **Deux lignes dessinées l'une SUR l'autre** dans « D'OÙ VIENT CE LOT » :
   la ligne « Marge libre » n'incrémentait jamais `y`, donc « Lot max autorisé »
   se peignait par-dessus — libellés et valeurs mélangés en une bouillie
   illisible (`Mlangeakilanetorisé`, `ma0g%`). Une ligne manquante, `y += 18`.
2. **« Marge avant limite » débordait sa colonne** de 80 px dans le bandeau
   d'accès rapide du flottant et mordait sur la colonne LOT : le libellé du
   PANNEAU était réutilisé dans une cellule six fois plus étroite. Libellé court
   dédié (`ROOM` / `MARGE` / `MARGEN`).
3. **L'aide se contredisait** : titre « RÈGLE 40% » et corps « seuls **100%** du
   profit comptent » sur un profil personnel. Le titre porte désormais le
   nombre dont il parle. Et « LÉGENDE » était écrit deux fois de suite.

⚠️ **Constat de méthode** : MT5 **ne recharge pas** l'indicateur à la
recompilation. Il faut changer d'unité de temps (ou le détacher/rattacher) —
sinon on regarde l'ancien binaire en croyant tester le nouveau.

### v3.21.33 — la queue de la relecture

- **Cliquer une ligne de position ramène le graphique sur son symbole** — le
  comportement de l'ancien panneau. La réécriture avait rangé ces lignes dans
  un fourre-tout « lignes d'information » qui se contente d'avaler le clic.
  Vaut pour la section POSITIONS et pour le tableau flottant.
- **Le conseiller pyramide parlait français quelle que soit la langue** : ses
  neuf phrases étaient écrites en dur. Elles passent par la table i18n.
- **Les drapeaux « 2e strike » étaient globaux** alors que la taille, la phase
  et le plan sont par login : une violation suivait le trader sur tous ses
  autres comptes. Ils sont désormais écrits et lus par login, avec la valeur
  globale comme graine de migration.
- **(0,0) est un coin légitime** : le tableau flottant y était traité comme
  « jamais placé » et revenait à sa position par défaut dès qu'on l'y déposait.
  Sentinelle à −1.
- **`CHART_EVENT_MOUSE_MOVE` est rendu à `OnDeinit`** : le drapeau était pris à
  l'attachement et jamais restitué.

**Ce qui reste ouvert et qui n'est pas de mon ressort** :

- l'identifiant de compte est toujours dans **l'historique git** des deux
  branches (le purger = réécriture + `force-push`, donc casse des clones) ;
- la **LICENSE** (« évaluation seule, non commerciale, aucun usage dans un
  produit ») contredit le README, qui explique comment installer l'outil et
  trader avec — et ne dit rien du `.ex5` fourni. Un texte juridique ne se
  corrige pas en passant.

### v3.20.32 — le travail lourd deux fois par seconde, et les infobulles coupées

- **Les lignes SL/TP étaient reconstruites sur TOUS les graphiques ouverts à
  chaque rafraîchissement** (500 ms), et depuis v3.19 à chaque clic en plus.
  C'est exactement la charge que l'ancien code plafonnait à 30 s en la
  qualifiant de « cause n°1 de gel ». Cadence ramenée à 2 s ; un changement de
  position les rafraîchit toujours immédiatement via `OnTradeTransaction`.
- **Le bloc news scannait le calendrier trois fois par appel** et reconstruisait
  une liste de 64 entrées, à 2 Hz, dans le thread d'interface. Cache de 15 s,
  avec le compte à rebours qui continue de descendre entre deux scans — il est
  affiché en minutes, la mise en cache est invisible.
- **Les infobulles étaient tronquées en plein milieu** : la description était
  écrite sur UNE ligne dans un bitmap fixe de 236 px, donc coupée au-delà d'une
  cinquantaine de caractères — dans les trois langues, et le français est plus
  long que l'anglais. Deux lignes avec retour sur espace, bulle à 58 px, et une
  marque explicite si ça déborde encore.

### v3.18.30 / v3.19.31 — la suite des 46 constats

**Le gate avait deux faux OK, corrigés en premier** — un instrument qui ment est
pire que pas d'instrument :

- le motif « chemin local » exigeait des **backslashes doubles** : un chemin
  utilisateur écrit normalement rendait **False**. Le contrôle de fuite le plus
  important d'un dépôt public ne matchait rien, et l'auto-test ne l'exerçait
  jamais — il n'injectait qu'une chaîne « login ». Motif réécrit (un OU deux
  backslashes, identifiant de terminal ajouté), injection ajoutée à l'auto-test.
- le contrôle des zones ne voyait que `ZAdd(..., RZ_LITTÉRAL)` : **toute zone
  passée en paramètre d'un helper** (`Toggle`, `LimRow`, `KV`, `Stepper`) lui
  était invisible. Il annonçait 119/119 alors qu'il y en a **149**.

Ce que le gate réparé a trouvé dans la seconde :

1. **Trois bascules dessinées, cliquables et MORTES** — `RZ_CFG_MVIOL`,
   `RZ_CFG_RVIOL`, `RZ_CFG_BE` sont déclarées **après** les add-ons, hors du
   bloc contigu du dispatch : leur clic était avalé, l'hôte jamais appelé.
   ⚠️ **Correction de v3.11** : j'y écrivais que l'hôte *ignorait* les deux
   « Violation » sur un profil non restreignable. C'était faux — **leur clic ne
   l'atteignait jamais**. Diagnostic plausible, et faux.
2. **L'identifiant du terminal MT5** était publié dans HISTORY.md → masqué.

Autres correctifs du même lot :

- **position du tableau flottant** restaurée *après* `Create()` : le bitmap
  restait à sa place par défaut pendant que les zones de clic partaient à la
  position mémorisée — visible ici, cliquable là. Lue avant `Create`, ré-ancrée.
- **état masqué** persisté (la croix s'annulait à chaque changement de TF) ·
  **cycleur de jour** basé sur `DaysInMonth` partagé (les années bissextiles
  étaient fausses) · **`RiskCockpit_logo.bmp` livré** : le README demandait de
  compiler sans la ressource que la source embarque · clé i18n dupliquée ·
  apostrophe manquante dans le texte de conformité.
- **le drag exige désormais une TRANSITION d'appui** : un pan du graphique qui
  traversait la bande de 24 px de l'en-tête capturait le tableau et coupait le
  défilement jusqu'au relâchement.
- **le thème choisi dans le shell mourait avec la frame** : jamais persisté
  (régression contre l'ancien panneau) et les lignes du graphique gardaient
  l'ancienne palette. Il remonte à l'hôte, qui l'écrit et reteinte le chart.
- **fausse alerte RED** : `rule_margin_pt` était une ligne de TEXTE sans alerte
  dans l'ancien code ; je l'avais mise à alerter contre une bande *recommandée*
  (20-30 %) — régler sa marge par trade à 40 % déclenchait un son RED contre un
  chiffre qu'aucun écran n'affiche.
- **les clics sont consommés immédiatement** : les intentions sont des slots
  uniques lus au timer, donc deux clics dans une même période de rafraîchissement
  n'en faisaient qu'un, sans retour visuel.

⚠️ **Et un défaut dans MON PROPRE test** : le cas « les pertes ne baissent pas
le plancher » comparait `RC_TrailingFloor(2100, 2000, 6)` **à lui-même** — il
passait quelle que soit l'implémentation. Remplacé par une vraie attente
(1980,00). Le script n'a toujours **jamais été exécuté**.

### v3.17.29 - ce qu'une relecture adversariale a trouvé dans MON code

Sept relecteurs indépendants ont lu le diff `main..dev` (16 versions livrées en
un jour, zéro test utilisateur), puis chaque constat est passé en
contre-expertise. J'ai re-vérifié chacun dans le code avant de toucher quoi que
ce soit. Huit défauts confirmés, tous introduits par la réécriture :

1. **La section AIDE mentait sur la version** : `d.version` était la chaîne
   codée en dur `"3.02"` alors que le binaire était `3.16`. **L'instruction de
   test que j'avais donnée à JR — « AIDE doit dire 3.16 » — était donc fausse :
   il aurait lu 3.02 et conclu que l'indicateur n'avait pas rechargé.** Une
   seule constante désormais, `RC_VERSION_STR`, posée à côté du `#property`.
2. **Toutes les alertes sonnaient PLUS TARD qu'avant la purge** : l'ancien code
   avertissait à 70 % (risque, journalier, total), **50 % sur un total
   *trailing*** — celui qui tue le compte — et 75 % (hyperactivité, msgs).
   `ShellRuleAlerts` avait tout aplati à 80 %. Les seuils par règle sont
   rétablis. Un outil de risque n'a pas le droit d'avertir plus tard.
3. **Le self-lock n'avait plus aucune sortie** : le bouton de déverrouillage
   est parti avec l'ancien panneau et rien ne l'a remplacé — jusqu'à 72 h
   enfermé. La capsule devient le contrôle de libération quand le verrou est
   actif (deux clics en 5 s, comme l'ancien double-confirm).
4. **La ligne « Hyperactivité » enregistrait `RZ_NONE`** : `RZ_NONE` signifie
   « rien touché », donc cliquer dessus tombait dans la règle du clic-à-côté
   et **refermait la section**. Elle a son propre identifiant de survol.
5. **Le cadenas était un carré vide** : `U+1F512` est hors du plan multilingue
   de base et `ShortToString` prend un `ushort` — tronqué en `U+F512` (zone
   privée). Le glyphe est retiré ; la teinte éteinte et la ligne de raison
   disaient déjà « verrouillé ».
6. **Un clic dans le panneau pouvait SUPPRIMER l'indicateur** : la navbar est
   dessinée en premier, donc ses zones gagnent la première correspondance. Le
   panneau collé en haut (`m_sideY = 0`) recouvre la navbar, et sa croix de
   fermeture tombe à quelques pixels de la croix **RETIRER**. Les zones de
   navbar sont maintenant exclues de tout clic qui atterrit dans le panneau.
7. **`RC_show_news` était lue au démarrage et plus jamais écrite** : un
   utilisateur v2 ayant coupé les news restait sans news pour toujours, sans
   aucun contrôle pour les rallumer. La clé est supprimée au démarrage.
8. **Le README promettait des alertes Telegram impossibles** : MQL5 interdit
   `WebRequest` dans un indicateur (c'est exactement pourquoi `RCNewsFeeder`
   est un *service*). L'envoi était tenté à chaque alerte et échouait en
   `err=4014`. La bascule est désormais dessinée **verrouillée avec sa raison**,
   l'appel est neutralisé, et le README le dit.

Reste à trancher : 46 autres constats de gravité moyenne ou faible, et
**29 contre-expertises n'ont jamais tourné** (limite de session atteinte en
plein run) — ce lot n'est pas vérifié.

### v3.16.28 - les formules de risque deviennent testables

Les douze contrôles statiques ne regardent que la mécanique. **Le cœur — les
chiffres qui décident si un compte est perdu — n'avait aucun test**, et le
plancher trailing n'était vérifié que par un commentaire.

- `Libraries/RC_Math.mqh` : les **8 fonctions pures** (aucun global, aucun
  compte, aucun symbole) sortent de l'indicateur — seuils de statut, dates de
  cycle, horodatages ISO 8601 du flux news, formats — plus
  **`RC_TrailingFloor()`**, extrait de deux copies inline de la formule. Il
  n'existe désormais qu'**une seule** implémentation du niveau où le compte est
  perdu ; les deux appelants l'utilisent.
- `Scripts/RC_SelfTest.mq5` : **30 cas**, à attacher à n'importe quel graphique.
  Aucun compte requis, rien n'est modifié, une ligne par cas dans le journal.
  Il inclut **le même** `RC_Math.mqh` que l'indicateur : ce qui est testé est
  ce qui tourne, pas une réimplémentation — une vérification qui ne franchit
  pas la frontière de langage ne vérifie rien.
- Couverture : oracle FN Instant 2K (pic 2003.28 → plancher 1883.28), plafond
  au break-even, pic sous la balance initiale, premier jour, garde-fous à zéro,
  add-on 10 % ; les bornes 79/80/99/100 des statuts ; bascules de mois, d'année
  et années bissextiles ; ISO 8601 avec décalage `-04:00` et forme `Z`.

⚠️ **Le script compile (0/0) mais n'a jamais été exécuté** — MT5 est fermé
depuis le crash. Sa première exécution en dira autant sur le test que sur le
code : une attente fausse s'y verra comme un FAIL. J'ai relu chaque attente
contre l'implémentation (seuils, bissextiles, sens des décalages horaires),
mais relire n'est pas exécuter.

### v3.15.27 - un numéro de compte MT5 traînait dans le dépôt PUBLIC

Contrôle déclenché par l'ajout du `.ex5` au dépôt en v3.13 : un binaire est
décompilable, donc il fallait savoir ce qu'il embarque. Scan des sources **et**
du binaire (ASCII + UTF-16), avec contrôle positif préalable — sans lui, un
verdict « propre » ne vaut rien.

- **Trouvé** : un commentaire portait un **numéro de compte MT5 en clair**
  (masqué ici : un changelog qui cite la valeur la republie), avec la taille et
  son equity, dans un commentaire du dépôt public. Le mandat l'interdit
  explicitement. Retiré ; l'information utile (l'oracle de calcul du plancher)
  reste, l'identifiant part.
- **Rien dans le `.ex5`** : les commentaires ne sont pas compilés, et le scan
  binaire ne remonte aucun jeton, chemin local, e-mail ni identifiant.
- Les 12 autres nombres à 8 chiffres sont des **numéros d'articles
  `help.fundednext.com`** cités en source des règles — pas des secrets.

⚠️ **L'historique git contient toujours ce numéro** (commits antérieurs). Le
retirer demanderait une réécriture d'historique + `push --force` sur un dépôt
public, ce qui casse les clones existants : **décision de JR, pas la mienne.**
Portée réelle : un login MT5 seul n'ouvre aucun accès (il faut le mot de passe
et le serveur), mais il identifie un compte prop et n'a rien à faire là.

### v3.14.26 - trois réglages qui ne faisaient plus rien, et des infobulles muettes

**Réglages morts** (un réglage qui n'agit pas est un bug vu du siège de
l'utilisateur — même famille que `InpAnchorX` retiré avec l'ancien panneau) :

- **`InpEnablePyramidSafe` — régression de ma part** : en v3.06 j'ai ramené le
  conseiller pyramide dans le shell **sans redemander si l'utilisateur l'avait
  activé**. Il s'affichait donc même désactivé. L'interrupteur est réhonoré.
- **`InpSoundOK`** : le fichier son « retour à OK » était réglable et n'a
  **jamais** été joué — `TryFireSoundAlert` ne connaissait que WARN et RED. Il
  sonne maintenant quand une règle repasse sous sa limite (jamais au démarrage :
  l'armement des alertes garde sa temporisation).
- **`InpRowHeight`** : géométrie d'un panneau qui n'existe plus → retiré.
  Audit : **45 inputs, 0 mort.**

**Infobulles de famille muettes** : `SetTip` est indexé par zone, donc une aide
poussée sur le premier membre (`tip_posrow` sur `RZ_POS_ROW0`) laissait les
rangs 1..7 **silencieux** — survoler la 1re position expliquait, survoler la 2e
n'affichait rien. `TipText` normalise désormais les familles (positions,
lignes flottantes, boutons CLOSE) sur leur premier membre. Cinq zones qui
n'avaient **aucune** aide en ont une (champ de copie du lot, poignée de
déplacement, croix de masquage, objectif de payout, msgs serveur).

Restent sans aide **60 zones qui n'en ont pas besoin** : items de menu (le nom
*est* l'aide), `+`/`−` des steppers et des cyclers, add-ons nommés en clair.

Le service compagnon `RCNewsFeeder` a été recompilé au passage : `0 errors`.

### v3.13.25 - ménage post-purge, et un trou i18n que le rituel a débusqué

Nettoyage de ce que la suppression de l'ancien shell avait laissé derrière :

- **105 clés i18n mortes** retirées (sur 336) — 4 chaînes chacune, dans un
  binaire public décompilable — plus **21 déclarations mortes** (`struct
  RCHit`, les 7 `RCF_*`, `VerdictResult`, `g_settings_tab`, `g_chip_*`,
  `RC_TITLE_HEIGHT`…) et 5 `SetLabel` que plus aucun `L()` ne lisait.
  **5753 → 5570 lignes.**
- Critère de suppression prudent : une clé n'est morte que si son littéral
  n'apparaît **nulle part** ailleurs (un `Tr(cond ? "a" : "b")` échappe à une
  recherche sur `Tr("x")`) et qu'aucun préfixe dynamique ne peut la construire.

**Deux erreurs attrapées par les contrôles, pas par le compilateur** — `Tr()`
renvoie la clé brute en secours, donc rien n'échoue à la compilation :

1. Ma boucle de suppression cherchait une ligne finissant par `);` ; les
   entrées suivies d'un commentaire (`); // E2 : was WARN`) ne matchaient pas,
   et la boucle **avalait les entrées voisines** — `chip_red`, `chip_warn` et
   `ins_tip_floor`, bien vivantes, étaient parties avec. Le contrôle « toute
   clé demandée existe-t-elle ? » les a rendues.
2. La sonde d'accents du rituel est tombée à **0** sur « Éligibilité ». En
   creusant : `RCL_PAYOUT` et `RCL_TARGET` **n'avaient jamais eu de
   traduction** depuis leur création — le shell les appelle dans un ternaire
   (`L(trailing ? RCL_PAYOUT : RCL_TARGET, …)`), angle mort de mon audit.
   En FR et en ES, la section COMPTE affichait donc de l'anglais. Corrigé, et
   l'audit des libellés parcourt désormais l'expression entière : **131 ids
   demandés, 131 poussés**.

`Result: 0 errors, 0 warnings` · 0 clé demandée introuvable · 0 libellé sans
traduction.

### v3.12.24 - le plancher trailing alerte à l'approche

Le plancher (`min(pic de balance − perte permise, balance initiale)`) est le
niveau où **le compte est perdu**. Il s'affichait en gris neutre, quelle que
soit la distance : la donnée la plus grave du panneau était la seule à ne rien
signaler. Il prend maintenant la couleur du ratio de DD total — mêmes seuils
80 % / 100 % que toutes les autres limites, aucune métrique inventée — et
passe en gras dès la zone d'alerte.

### v3.11.23 - deux boutons FANTÔMES : cliquables, sans effet, sans un mot

Audit demandé par JR (« être sûr que tous les boutons marchent »), poussé au
delà du câblage : non pas « la zone a-t-elle un handler » mais **« l'hôte
agit-il vraiment, dans TOUS les états ? »**. Deux contrôles échouaient :

- **« Outils de risque »** : `ShellApplyCfg` ne l'applique que
  `if (PlanIsPersonal())`. Sur un plan prop — le cas de JR — le clic ne faisait
  **rien**, et rien ne le disait.
- **« Violation marge » / « Violation risque »** : sur un profil que
  `ProfileCanBeRestricted()` refuse, la résolution suivante remet les deux
  drapeaux à `false` : la bascule s'inversait puis revenait aussitôt.

Correctif : `Toggle()` accepte un état **verrouillé** — cadenas, teinte éteinte,
et la **raison écrite sous la ligne** (traduite EN/FR/ES). Le réglage garde sa
place (il existe), mais il ne ressemble plus à un bouton qui agit. Même règle
que le bouton CLOSE désactivé du tableau flottant.

Le reste de l'audit ne trouve rien : steppers **6/6 · 5/5 · 4/4** lignes
affichées ↔ appliquées, cascade **5/5**, cycle **3/3**, et les add-ons
parcourent les 7 drapeaux dans le **même ordre** des deux côtés (un décalage
aurait basculé un add-on à la place d'un autre, sans erreur visible).

`Result: 0 errors, 0 warnings` · 129 libellés utilisés, **0 sans traduction**.

### v3.10.22 - le panneau se dimensionne sur ce qu'il affiche

Même mécanisme que le bug du tableau flottant signalé par JR, resté en place
ailleurs : en mode **section unique**, `RenderSide` dessinait le corps sans
jamais vérifier qu'il tenait. Tout ce qui dépassait `m_sideH` était peint
**hors du bitmap** — invisible, sans un mot. Le mode sidebar, lui, tronquait
déjà honnêtement ; c'est ce qui a masqué le trou.

- Chaque section **se mesure** à son premier rendu (`m_secH[8]`), et cette
  mesure dimensionne la surface pour toutes les frames suivantes. La boucle
  converge en une frame : la hauteur mesurée devient la hauteur créée, qui
  redonne la même mesure.
- Si la section reste plus haute que le graphique ne le permet, elle **le
  dit** (`▼ agrandis la fenêtre`) au lieu de perdre sa fin.
- Les clics fantômes sont déjà couverts : le filtre de confinement borne les
  zones à la hauteur peinte, donc une zone tronquée n'est pas cliquable.

La section POSITIONS venait justement de grossir (conseiller pyramide), et
c'est elle qui aurait débordé la première sur un petit graphique.

Compilation `0 errors, 0 warnings` ; audits i18n inchangés (157/192 libellés,
149/192 zones, 0 identifiant sans traduction).

### v3.09.21 - les accents sont PROUVÉS, sans allumer le terminal

La v3.08 laissait un doute assumé : impossible de vérifier que les accents
survivaient au compilateur, faute d'instrument. Il en existait un.

- **Les `#property` sont stockées EN CLAIR (UTF-16LE, non compressées) dans
  l'en-tête du `.ex5`** — contrairement aux chaînes du corps, qui sont
  compressées et rendaient ma première sonde muette dans les deux sens.
- Protocole : `#property copyright` porte temporairement
  `ENCPROBE RÈGLES Année señal boîte à outils`, compilation, puis recherche de
  la chaîne dans le binaire **et** de sa variante mojibake (`utf-8` relu en
  `latin-1`).
- **Contrôle positif d'abord** : `ENCPROBE` doit être trouvé, sinon
  l'instrument ne mesure rien et on ne conclut pas. Ce garde-fou a servi : la
  1re tentative passait par `#property description`, qui **n'est pas** stockée
  en clair → verdict INDÉTERMINÉ, aucune conclusion tirée.
- **Résultat : chaîne accentuée trouvée telle quelle · variante mojibake
  absente ⇒ MetaEditor lit bien la source en UTF-8 grâce au BOM.**
- Les deux sondes sont retirées (`copyright` restauré à l'identique, `Print`
  d'`OnInit` supprimé : la preuve statique vaut mieux qu'une ligne de journal
  qui attend un rechargement).

⚠️ Ce que cela ne prouve pas : le RENDU à l'écran (police, largeur des
capsules). Ça, seule une capture de JR le dira.

### v3.08.20 - les vrais accents en FR et en ES

- **98 entrées de la table i18n ré-accentuées** (FR + ES) par table de mots +
  surcharges de phrases pour les cas qu'un mot ne peut pas trancher : `a`/`à`,
  `ou`/`où`, `esta`/`está`, `perdida` (adjectif) vs `pérdida` (nom).
- **Le rapport a été relu ligne à ligne, et il contenait 6 faux positifs** que
  la table de mots ne pouvait pas voir : `FundedNext recommande 20-30%` et
  `resserre le plafond` sont des VERBES (pas d'accent), `cuenta perdida` est un
  adjectif (pas `pérdida`), `Sección unica` devait être `única`, `no envia`
  devait être `envía`, `seuil configure` devait être `configuré`. Corrigés par
  surcharge, puis re-vérifiés un par un.
- Fixes ponctuels : `boîte à outils`, `perdre à sa SL`, `À PROPOS`, `À VENIR`,
  `(100 = sûr)`, `âge`, `présence`, `ámbar`, `Año`.

⚠️ **La preuve bout-en-bout n'est PAS acquise.** J'ai sondé le `.ex5` pour y
retrouver les chaînes accentuées : **aucune** — mais mon contrôle positif
(chercher une chaîne ASCII connue) échoue aussi, donc **l'instrument ne mesure
rien** : MQL5 compresse ses chaînes dans le binaire. Ce qui est établi : le BOM
UTF-8 est bien unique (c'est la condition qui avait manqué en v2.14.06 et
provoqué le mojibake), la compilation est propre, et le fichier portait déjà
des accents rendus correctement en v2.x. Une sonde `Print` temporaire a été
laissée dans `OnInit` : au prochain attachement, le journal MQL5 montrera
`RÈGLES / PYRAMIDE / FENÊTRE NEWS` - accentué ou non. Elle sera retirée
ensuite.

🔎 **Constat de terrain : le terminal n'a PAS rechargé l'indicateur depuis
13:48.** Le journal ne montre aucune ré-initialisation de RiskCockpit après
cette heure, alors que 6 compilations ont suivi. JR teste donc un build
antérieur à la parité, à la purge et à l'i18n : il faut retirer puis remettre
l'indicateur (ou redémarrer le terminal) pour charger `3.08`.

### v3.07.19 - i18n : tout ce que l'utilisateur lit devient traduisible

Deux plafonds silencieux expliquaient l'essentiel du francais residuel :

- **`RCS_L_MAX` valait 64 pour 95 identifiants de libelles** : `SetLabel()`
  jetait sans un mot tout id >= 64, donc **31 libelles ne pouvaient PAS etre
  traduits** et affichaient leur defaut francais dans les trois langues.
- **`RCS_TIP_MAX` valait 96 pour 149 zones** : meme mecanique sur les
  infobulles. Les deux gardes etaient des `if` sans `else` - un controle qui
  echoue en silence n'est pas un controle. Plafonds portes a 192 **et** un
  `Print` explicite si un id depasse.

Ensuite le contenu :

- **42 chaines codees en dur** passent par `L(id, "...")` : titres de sections,
  etat discipline, section news, aide (legende, regle 40%, marge de survie,
  mention read-only), reglages, messages du bandeau, cellules du rail.
- **89 libelles pousses par l'hote en EN / FR / ES** (`AddTr`) - 62 nouveaux
  identifiants + 27 qui existaient mais que l'hote n'avait jamais cables.
- **Tous les defauts du code sont desormais en ANGLAIS** (regle JR : le code en
  anglais), y compris les 58 infobulles de repli : l'anglais est la bonne
  langue de repli pour un produit vendu surtout en anglais, et les traductions
  arrivent de la table i18n de l'hote.
- Deux infobulles mentaient encore ("selection : lot 2", promesse d'un lot
  precedent) : les chips SYMBOLE et UNITE DE TEMPS ouvrent bien un menu.
- `SecSoon` (placeholder mort depuis que chaque section a un corps) supprime.

Audits : **157 ids <= 192**, **149 zones <= 192**, **0 id utilise sans
traduction**, 0 cle `Tr()` sans `AddTr`, 0 langue vide, 1 seule chaine
francaise restante corrigee. `Result: 0 errors, 0 warnings`.

### v3.06.18 - suppression de l'ancien shell (ordre JR)

> "si tu as tout recupere de toute facon on a l'ancienne version dans le git
> donc supprime l'ancien shell"

La parite ayant ete retablie en v3.06.17, l'ancien panneau est retire.

- **70 fonctions supprimees** : canvas panel (`BuildPanel`, `RepaintCanvas`,
  `DrawTitleBar`, `DrawAccountStrip`, `DrawRuleRow`, `DrawFooter`...), modal
  de reglages (`DrawSettingsOverlay` et ses 12 helpers), moteur de hit-test
  legacy (`HitAdd`/`HitTest`/`DrawFace`/`PaintFaces`), drag du panneau,
  overlays (`DrawHardLock`, `DrawTiltBanner`), FX canvas, barres TF et
  symboles recents, `UpdateRow`/`ComputeVerdict`/`UpdateClockBlinker`.
- **26 globales mortes** retirees (ancre du panneau, etat du modal, tableau de
  hit-test, canvases `g_kit`/`g_modal_kit`/`g_fx`, blinker...).
- **4 inputs supprimes** : `InpShellV2` (l'interrupteur v2/v3 n'a plus de sens),
  `InpAnchorX`, `InpAnchorY`, `InpPanelWidth` - un reglage qui ne fait plus rien
  est un bug du point de vue de l'utilisateur.
- `RefreshPanel()` ne fait plus que deleguer a `ShellRefresh()` : **un seul
  chemin de rendu**, plus de garde `if (InpShellV2)` nulle part.
- `CHARTEVENT_OBJECT_CLICK` n'a plus rien a router : le shell est 100 %
  hit-testing, aucun controle natif ne subsiste (hors les 2 champs de copie).

**Bilan : 8847 -> 5561 lignes (-3286, -37 %)**, `.ex5` 551 ko -> 406 ko (-26 %),
compilation 14,0 s -> 6,8 s.

Audits statiques apres purge : **119/119 zones cliquables gerees (0 orpheline)**,
**124/124 champs du modele remplis**, 11/11 bascules de config avec leur branche
hote, `Result: 0 errors, 0 warnings`.

⚠️ Reste a valider par l'usage (JR) avant merge sur `main`.

### v3.06.17 - parite : ce que la bascule v3 avait rendu MUET

Audit demande par JR ("verifie que tu as bien ajoute tous les outils de
l'ancien shell"). Trois fonctions vivaient DANS le corps legacy que la garde
`if (InpShellV2) return;` court-circuite : elles ne bugguaient pas, elles ne
tournaient plus du tout.

- **Alertes son + Telegram MUETTES depuis la bascule** : elles etaient portees
  par `UpdateRow()`, appele uniquement par l'ancien `RefreshPanel()`. Nouveau
  `ShellRuleAlerts()` : memes seuils (80 % / 100 %), meme registre `g_rows`,
  meme cooldown Telegram par regle, mais alimente par le modele du shell.
- **Conseiller PYRAMIDE / panier perdu** : `RefreshPyramidLine()` ecrivait dans
  `footer_l4`, un label qui n'existe plus. Refactorise en
  `BuildPyramidLine(line, stat)` ; le shell l'affiche dans la section
  POSITIONS (ou ajouter, ou remonter TOUS les SL, ce que ca verrouille).
- **Risque de report week-end invisible** : l'horloge legacy clignotait
  "WEEKEND HOLD / FLATTEN" et declenchait l'alerte. Le shell n'avait ni l'un
  ni l'autre -> le bandeau de securite porte desormais l'avertissement, et
  `FireWeekendAlert()` est appele depuis le chemin du shell.
- **Lignes de break-even figees** : redessinees a chaque refresh du shell.
- **Horloge de la navbar teintee** rouge/ambre quand un evenement contraignant
  tombe dans l'heure (le compte a rebours, lui, reste dans la cellule NEWS).
- Compilation : `Result: 0 errors, 0 warnings`.

> Travail desormais sur la branche **dev** (regle JR du 04/09) ; `main` ne
> recoit que les versions X.YZ abouties.

### v3.05.16 - le tableau flottant devient permanent (retour JR, 5 defauts)

- **Le flottant disparaissait** : sa geometrie (`m_fltOn`, `m_fltH`) n'etait
  calculee que dans `ReadChart()`, appele a la creation et sur CHART_CHANGE.
  Une position ouverte ENTRE deux layouts ne redimensionnait donc jamais le
  bitmap : les lignes etaient dessinees hors surface, donc invisibles. La
  hauteur voulue est maintenant dans `FloatWantH()`, et `Tick()` recree les
  surfaces des qu'elle bouge (meme mecanique que le bandeau d'alerte).
- **Toujours affiche** (demande JR) : `m_fltOn = !m_fltHidden`. A plat il garde
  son cadre et dit "Aucune position ouverte". La croix le masque pour la
  session ; la cellule POS du rail est le chemin de retour.
- **Acces rapide sur le flottant** (demande JR) : bandeau MARGE / LOT / NEWS
  sous l'en-tete, chaque cellule cliquable ouvre la section correspondante.
- **Le drag ne fait plus defiler le graphique** : `CHART_MOUSE_SCROLL` est pris
  pendant le glisser et rendu au relachement (`Destroy()` le rend aussi, il ne
  peut donc pas rester coupe).
- **Bouton CLOSE par position, DESACTIVE** : un indicateur ne passe pas d'ordre
  et ce produit n'en passera pas. La pastille est grisee, le clic n'appelle
  aucune fonction de trade - il met en evidence la ligne "Fermeture : version
  EA". Tooltip en 3 langues.
- Compilation : `Result: 0 errors, 0 warnings` (MetaEditor du terminal D0E8).

> ATTENTION topologie : `C:\Program Files\FundedNext MT5 Terminal\metaeditor64.exe`
> resout ses includes sur SON dossier de donnees (`89FE26...`), dont
> `MQL5\Libraries\` est VIDE -> `error 106` sur les 4 .mqh. Le seul editeur
> valide pour ce projet est `C:\Program Files\MetaTrader 5\metaeditor64.exe`.

### v3.04.15 — 2026-09-04 — parity complete: add-ons, violations, self-lock, cycle, copy-max, BE

The last six things the legacy modal could do and the shell could not. Feature parity is reached;
the old panel is now kept only as a fallback.

- **Add-ons** are toggles again, in ACCOUNT — and only those the current plan actually allows are
  listed (an add-on you cannot buy on this plan is noise). Toggling one re-resolves the profile,
  because add-ons change the rules themselves (95 % split, no-min-days, 10 % DD…).
- **Post-violation caps** (margin / risk) move next to the discipline state rather than into a
  settings tab: they *change the limits*, so they belong where the limits are read.
- **Self-lock** arms in **two clicks** — the button asks "CONFIRMER ?" first, and any click
  elsewhere disarms the question. The legacy modal armed a multi-hour full-panel STOP on a single
  click; that is too easy to hit by accident.
- **Cycle start date** (year / month / day) as three cyclers, clamped so an impossible date
  (31 February) can never be built.
- **Copy-max**: the max lot gets its own copyable box under the suggested one.
- **Break-even lines** toggle, which draws or clears the chart-side lines immediately.

Audit: **0 orphan zones** out of 117 drawn, every model field filled. Compiled `0 errors,
0 warnings`.

### v3.03.14 — 2026-09-04 — two orphan click zones (from v3.01.12)

The static zone audit caught two zones added with the rule-parity rows that were **drawn but not
handled**: the *Profit target* row and the *Server messages* row. A click on either fell through to
the auto-collapse, so the panel closed under the user's finger instead of doing nothing.

Both are info rows, so the fix is to swallow them — and rather than adding two more `==` tests, the
whole family of hover-only rows is now handled as **one contiguous range**, which is what stops the
next one from being forgotten. The HISTORY note of v3.02.13 has been corrected: it claimed zero
orphans before the audit had answered.

Audit after the fix: **0 orphan zones** out of 99 drawn. Compiled `0 errors, 0 warnings`.

### v3.02.13 — 2026-09-04 — settings steppers and the plan cascade

The last thing the shell could not do that the legacy modal could: **change a setting**. Both are
in now, and both write to the *same* globals and GlobalVariables the modal writes — one product,
one configuration.

- **SETTINGS**, four sub-tabs so the tunables fit without scrolling: *Risk* (SL %, TP %,
  margin/trade, risk/trade, planned trades N, profit split), *Discipline* (tilt N, tilt window,
  cooldown N, cooldown minutes, self-lock hours), *Advanced* (comfort %, refresh ms, post-violation
  margin and risk caps), *Display* (the toggles, unchanged). Same clamps as the modal; the refresh
  stepper re-arms the timer, the comfort stepper re-applies the padding.
- **ACCOUNT**, the plan cascade is editable at the top of the section: broker → type → phase →
  size → account type, each as a `< value >` cycler, with the modal's snapping rules (a plan can
  never end up on an illegal size or phase) and a full profile re-resolve on every click.
- The shell **asks**, the host **writes**: a click only records "row N, +1/-1"; every mutation and
  every persistence call lives on the host side.
- Sections carrying controls (settings, account) get a taller panel, the way StrategyDeck gives its
  copilot more room.

Model fields all filled, compiled `0 errors, 0 warnings`. **The zone audit run with this commit
reported two orphans** (`RZ_TIP_TARGET`, `RZ_TIP_MSGS`) — see v3.03.14, which fixes them; the
"0 orphans" claim first written here was premature.

### v3.01.12 — 2026-09-04 — rule parity: the 7 legacy rows the shell was missing

The legacy panel showed eleven rule rows; the shell showed four. The seven that were missing are
back, each in the section where it belongs rather than in one long list:

- **LOT** — *Max lot allowed*, with **which cap binds** (per-trade margin target / remaining
  cumulative room / broker free margin).
- **LIMITS** — *Quick Strike ratio*, metered like the other rules.
- **DISCIPLINE** — *Hyperactivity* (trades vs daily cap) and *Server messages* (orders touched).
- **NEWS** — the *news-window meter* (ramps over the hour before, full inside the window) and the
  *news-trading stats* (count, P&L, eligible share).
- **ACCOUNT** — *Profit target*, relabelled *Payout eligibility* on a trailing profile, with its
  progress meter.

The max-lot maths was **extracted into `Live_MaxLot()`** and is now called by both the legacy row
and the shell. Two copies of a risk number is how they start disagreeing — the health badge bug
fixed in the previous version was exactly that failure mode.

Compiled `0 errors, 0 warnings`.

### v3.00.11 — 2026-09-04 — shell on by default, floating positions table, health badge fixed

`InpShellV2` now defaults to **true**: the rail *is* the interface. The legacy panel is kept in the
code (not purged) and is one input away.

- **Health badge bug (visible on a capture, fixed).** The navbar read `SAIN 100/100` while the rail
  showed a red `100%` and `DD total 59.34 / 8.0%`. The badge came from `ComputeVerdict()`, which
  reads `g_rows[]` — and `g_rows` is filled by `RefreshPanel()`, which the shell short-circuits. So
  the badge was frozen on its startup value. It is now derived from the **same live ratios the rail
  draws**: one source, no stale read (same thresholds, profit target still excluded).
- **Floating positions table** (StrategyDeck-style): appears by itself as soon as a trade is open,
  disappears when the last one closes. Per row: status dot, symbol, side, volume, P&L, age and a
  red `SANS SL` flag; header carries the count and the total floating P&L. Draggable by its header,
  clamped inside the chart, position persisted per login, and hideable for the session.
- Labels the capture showed truncated (`Spr`, `Com`, `libre`) now read `Spread`,
  `Commission / lot`, `Marge libre` — they were reusing the legacy footer's abbreviations.

Compiled `0 errors, 0 warnings`.

### v2.18.10 — 2026-09-04 — copy-lot: the shell's one native control

The suggested lot is the number that gets pasted into the order ticket, and a canvas cannot be
selected — so this one value needs a native `OBJ_EDIT`. It is the last service the legacy panel
had and the shell did not.

- The shell **reserves the rectangle** inside the LOT section and registers a **no-op click zone**
  under it: a click on the box (or its border) must never collapse the section — the trap the
  playbook warns about.
- The host owns the object (`RC_V3_copylot`), so it lives and dies with the rest of the
  `RC_`-prefixed objects, and it is themed from the shell's own palette.
- It appears only while the LOT section is open and a lot is actually available.

Compiled `0 errors, 0 warnings`.

### v2.17.09 — 2026-09-04 — restore the UTF-8 BOM on the source

`Indicators/RiskCockpit.mq5` lost its BOM during today's edits (it went out in v2.14.06). The file
stayed valid UTF-8 and every compile passed, so nothing failed loudly — but MetaEditor treats a
BOM-less file as ANSI, which would have turned every accented literal (`Éligibilité`, `Thème`,
`PRECAUCIÓN`) into mojibake in the panel. Silent corruption, caught by the pre-commit ritual, not
by the compiler.

The pre-commit check is now: **single** BOM (a doubled one is `error 110: unknown symbol 0xFEFF`,
which is how the first fix attempt failed), accented probes present, balanced braces/parens, and
`.ex5` newer than `.mq5`.

`Libraries/RC_ShellUI.mqh` holds zero non-ASCII bytes by design, so its lack of a BOM is
harmless — its French fallbacks are written unaccented.

Compiled `0 errors, 0 warnings`.

### v2.16.08 — 2026-09-04 — shell tooltips go through the product's i18n

The 40-odd hover bubbles were the last block of hard-coded French in the shell. They now flow
through the same `Tr()` table as everything else: one entry per bubble, `"title|description"`
packed in a single translation, split by the shell.

- `SetTip(zoneId, "title|desc")` on the shell + `Zid*()` accessors, so the host addresses its
  tooltips without importing the zone enum.
- 49 new keys, EN/FR/ES, covering the 8 rail cells, the chevron, the 9 navbar chips, the panel
  chrome, the limit / lot / news / discipline info rows, the 10 settings toggles, the safety band,
  a position row, the account card and the version line.
- The French wording stays in the shell as the fallback and the reference.

Compiled `0 errors, 0 warnings`.

### v2.15.07 — 2026-09-04 — menu theme aligned on StrategyDeck v2

The dropdown built in the previous lot drew its selected item as a flat tinted highlight, which
reads as a *different* control from the rest of the shell. The reference (StrategyDeck's
`SDDeckUI.mqh`) paints the selected item as a full **accent → accent2 gradient capsule carrying
dark text** — the same language as the rail chevron and the active segment.

- Selected item: gradient capsule + dark text (was: flat tint + accent text).
- 26 px item pitch, items centred, card inset 1 px, softer shadow (4/60 instead of 6/70).
- Per-mode typography: Segoe UI for timeframes, Consolas for symbols.
- Symbols longer than 12 characters are truncated to `11..` so an item can never overflow.

Checked first, as the mandate asks: the two copies of `JR_CanvasUI.mqh` differ by **one comment
line** — the kit carries no menu style and nothing had to be ported from it. The theme lives at
panel level, and only there.

Compiled `0 errors, 0 warnings`.

### v2.14.06 — 2026-09-04 — v3 shell: rail + on-demand panel (lots 1 → 2b)

New space architecture, ported from the StrategyDeck v2 shell, **behind `InpShellV2` (default
`false`)**: with the input off nothing changes, so the shipped panel is untouched.

- **`Libraries/RC_ShellUI.mqh` (new)** — 6 themes (3 palettes × dark/light), `RCDeckData`
  snapshot, anchor-relative hit-testing (zero `OBJ_BUTTON`), one render path
  (`ZReset` → surfaces → a single `ChartRedraw`), anchor clamp everywhere, hover-intent tooltips.
- **36 px rail** glued to the right edge, centred band ~60 % of the chart height, **8 cells**
  (LIM, POS, LOT, NEWS, DISC, CPT, CFG, HELP), each showing a live micro-state. At rest the tool
  occupies 36 px instead of 620 × 668.
- **340 px panel** opening in front of the clicked cell (same cell toggles it shut), plus a
  chevron for the full sidebar; sections: limits, positions, lot advisor, news, discipline,
  account, settings, help.
- **Full-width safety band** above the navbar for a hard lock / SL guard / tilt: the alert is
  never what gets hidden.
- **Navbar** (750 × 34, responsive): symbol and timeframe dropdowns, health badge, vitals,
  palette cycle, dark/light, clock, remove.
- **Settings toggles** click through to the *same* globals and persistence the modal uses — the
  shell never mutates the model itself.
- **i18n**: the shell ships French defaults, overridden by the product's own `Tr()` table
  (28 new keys, EN/FR/ES), so one translation table serves both UIs.
- `JR_CanvasUI.mqh`: `Text()` and `TextSizeGet()` added (the kit is otherwise identical to
  StrategyDeck's copy).
- Fix: `DestroyAllObjects()` wipes the whole `RC_` namespace, shell canvases included — the shell
  is now recreated after it, or the rail vanished when a discipline lock cleared.

Compiled `0 errors, 0 warnings` in the topology above.
