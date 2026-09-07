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
| Includes (all four) | `…\MQL5\Libraries\` : `CChallengeProfileCatalog.mqh`, `CPyramidEngine.mqh`, `JR_CanvasUI.mqh`, `RC_ShellUI.mqh` |
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
| `Services/RCNewsFeeder.mq5` | `MQL5\Services\RCNewsFeeder.mq5` |

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
