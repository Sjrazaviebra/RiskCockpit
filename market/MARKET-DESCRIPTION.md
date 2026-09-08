# RiskCockpit — description de la fiche MQL5 Market

> Trois versions : EN, FR puis ES. **L'anglais est obligatoire** sur le Market ; le français et
> l'espagnol sont des traductions recommandées, chacune dans son onglet de langue du formulaire.
> À coller dans le formulaire du produit **180509**.
>
> ⛔ Écrites contre les **règles officielles Part IV** : aucune garantie ni promesse de bénéfice ·
> aucun superlatif · aucun backtest présenté comme du réel · aucun lien externe · aucun titre
> sensationnel · phrases simples, sans argot ni abréviations.
>
> ⚖️ Le parti pris : **cet outil ne parle jamais de gain.** Il parle de règles, de plafonds et de
> distance à la brèche. C'est le sujet du produit, pas une prudence de façade — et c'est
> vérifiable à l'écran, ligne par ligne.

---

## 🇬🇧 ENGLISH

**RiskCockpit — a rule-monitoring dashboard for prop-firm traders.**

RiskCockpit measures your account against the rules of your funding program while you trade. It
never opens, closes or modifies a position: it reads, it computes, and it says what it finds.

**What it watches**

- **Distance to every limit that can end an account** — daily drawdown, overall drawdown, and the
  trailing floor of instant-funding accounts, which follows the realised balance high rather than
  the starting balance. Each rule has its own warning threshold; the panel warns at that threshold
  and not at a single flat one.
- **Open risk, and the risk your firm actually scores.** A prop firm reads the stop you posed when
  the position opened. Moving that stop afterwards does not lower what the firm counts, so the
  panel carries both figures and marks the difference.
- **Cumulative margin, per-trade risk, planned trades**, against the caps of the active profile.
- **Quick Strike, hyperactivity and server-message counters**, when the active program defines them.
- **News windows.** Restricted events are classified from the ForexFactory calendar and the panel
  shows the countdown to the next binding one, with the share of the profit your program keeps for
  a trade taken inside that window — including the programs that keep none.

**What it advises**

A lot size, computed from your risk per trade, your stop distance and the room actually left under
the nearest limit. It is capped so that a losing trade cannot take the account past a limit, and
when the result falls under the broker minimum it says so instead of printing a number you cannot
use. The number sits in a selectable box: click it, copy it, paste it into the order ticket.

**Discipline tools**

A three-step lock ladder. Your own **self-lock**, armed in two clicks and released in two more — a
pact you cannot leave is a trap, not discipline. A **hard lock** when the daily drawdown reaches
80% of its cap. A **cooldown** after several consecutive losses. Plus tilt detection: too many
entries inside your window, or a new position larger than your last closed loss. While a lock
holds, the controls that would end it or loosen a limit are disabled — including the button that
removes the tool from the chart.

**Programs**

A built-in catalogue of challenge profiles: FundedNext Stellar 1-Step, 2-Step, Lite and Instant,
with their add-ons. Profiles compatible with FTMO, E8, The5ers and MyFundedFX rule sets are
included. Every limit shown is derived from the profile you select — change the profile and every
number follows.

**The interface**

A 36-pixel rail on the right edge of the chart, one cell per domain, each showing a live
micro-state. Click a cell and a panel opens in front of it. A chevron stacks every section into a
full sidebar. The top bar carries the three numbers that decide the next click: room to the nearest
limit, advised lot, next news. A floating table lists open positions with their age, their P&L and
a missing-stop flag.

**Built-in manual**

The HELP section is the documentation: a step-by-step usage guide, then one fold-out per surface
and per section, listing every element with what it means. Nothing to read elsewhere before using
the tool.

**Read-only, by construction**

The indicator has no trading function in it at all. It cannot send an order, and it cannot modify
one. Sound alerts fire on status changes, with the files you choose.

**Interface in English, French and Spanish.**

**Installation.** Attach the indicator to a chart. For the ForexFactory news classification, also
add the companion service `RCNewsFeeder` from the Navigator and allow the calendar URL in
Tools → Options → Expert Advisors. Without the service, news rules fall back to the MetaTrader
calendar, which classifies events differently; the panel says which source is in use.

**No profit claim is made anywhere in this product.** It measures rules and distances. What you do
with them is your decision.

---

## 🇫🇷 FRANÇAIS

**RiskCockpit — un tableau de bord des règles pour les traders en prop firm.**

RiskCockpit mesure ton compte face aux règles de ton programme de financement pendant que tu
trades. Il n'ouvre, ne ferme et ne modifie jamais une position : il lit, il calcule, et il dit ce
qu'il trouve.

**Ce qu'il surveille**

- **La distance à chaque plafond qui peut mettre fin à un compte** — perte journalière, perte
  totale, et le plancher glissant des comptes à financement immédiat, qui suit le plus haut de la
  balance réalisée et non la balance de départ. Chaque règle a son propre seuil d'alerte ; le
  panneau prévient à ce seuil, pas à un seuil unique appliqué à tout.
- **Le risque ouvert, et le risque que la firme compte réellement.** Une prop firm lit le stop posé
  à l'ouverture de la position. Le remonter ensuite ne baisse pas ce qu'elle compte : le panneau
  porte les deux chiffres et marque l'écart.
- **La marge cumulée, le risque par trade, les trades prévus**, face aux plafonds du profil actif.
- **Les compteurs Quick Strike, hyperactivité et messages serveur**, quand le programme actif les
  définit.
- **Les fenêtres news.** Les événements restreints sont classés depuis le calendrier ForexFactory,
  et le panneau affiche le compte à rebours du prochain événement contraignant, avec la part du
  profit que ton programme conserve pour un trade pris dans cette fenêtre — y compris les
  programmes qui n'en conservent aucune.

**Ce qu'il conseille**

Une taille de lot, calculée depuis ton risque par trade, ta distance de stop et la marge réellement
restante sous le plafond le plus proche. Elle est bornée pour qu'un trade perdant ne puisse pas
faire passer le compte au-delà d'un plafond, et quand le résultat tombe sous le minimum du courtier
il le dit au lieu d'afficher un nombre inutilisable. Le chiffre est dans un champ sélectionnable :
clic, copie, collage dans le ticket d'ordre.

**Outils de discipline**

Une échelle de verrous à trois marches. Ton **auto-verrou**, armé en deux clics et libéré en deux
autres — un pacte dont on ne peut pas sortir est un piège, pas de la discipline. Un **verrou dur**
quand la perte journalière atteint 80 % de son plafond. Une **pause** après plusieurs pertes
consécutives. Plus la détection de tilt : trop d'entrées dans ta fenêtre, ou une position plus
grosse que ta dernière perte fermée. Pendant qu'un verrou tient, les contrôles qui le lèveraient ou
qui desserreraient une limite sont désactivés — y compris le bouton qui retire l'outil du graphique.

**Programmes**

Un catalogue de profils intégré : FundedNext Stellar 1-Step, 2-Step, Lite et Instant, avec leurs
add-ons. Des profils compatibles avec les jeux de règles FTMO, E8, The5ers et MyFundedFX sont
inclus. Chaque plafond affiché découle du profil choisi — change le profil et tous les chiffres
suivent.

**L'interface**

Un rail de 36 pixels sur le bord droit du graphique, une cellule par domaine, chacune portant un
micro-état en direct. Un clic sur une cellule ouvre un panneau devant elle. Un chevron empile
toutes les sections en une barre latérale complète. La barre du haut porte les trois chiffres qui
décident du prochain clic : marge jusqu'au plafond le plus proche, lot conseillé, prochaine news.
Une table flottante liste les positions ouvertes avec leur âge, leur P&L et l'absence de stop.

**Manuel intégré**

La section AIDE est la documentation : un guide d'utilisation pas à pas, puis un volet par surface
et par section, listant chaque élément avec ce qu'il signifie. Rien à lire ailleurs avant de se
servir de l'outil.

**En lecture seule, par construction**

L'indicateur ne contient aucune fonction de trading. Il ne peut pas envoyer un ordre, ni en
modifier un. Des alertes sonores se déclenchent aux changements de statut, avec les fichiers de ton
choix.

**Interface en anglais, français et espagnol.**

**Installation.** Attache l'indicateur à un graphique. Pour la classification news ForexFactory,
ajoute aussi le service `RCNewsFeeder` depuis le Navigateur et autorise l'URL du calendrier dans
Outils → Options → Expert Advisors. Sans le service, les règles news retombent sur le calendrier
MetaTrader, qui classe les événements différemment ; le panneau indique quelle source est utilisée.

**Aucune promesse de gain n'est faite dans ce produit.** Il mesure des règles et des distances. Ce
que tu en fais est ta décision.

---

## 🇪🇸 ESPAÑOL

**RiskCockpit — un panel de control de reglas para traders de prop firm.**

RiskCockpit mide tu cuenta frente a las reglas de tu programa de financiación mientras operas.
Nunca abre, cierra ni modifica una posición: lee, calcula y dice lo que encuentra.

**Lo que vigila**

- **La distancia a cada límite que puede terminar una cuenta** — pérdida diaria, pérdida total y el
  suelo móvil de las cuentas de financiación inmediata, que sigue el máximo del balance realizado y
  no el balance inicial. Cada regla tiene su propio umbral de aviso; el panel avisa en ese umbral y
  no en uno único aplicado a todo.
- **El riesgo abierto y el riesgo que la firma cuenta realmente.** Una prop firm lee el stop
  colocado al abrir la posición. Moverlo después no reduce lo que ella cuenta: el panel lleva
  ambas cifras y marca la diferencia.
- **El margen acumulado, el riesgo por operación y las operaciones previstas**, frente a los
  límites del perfil activo.
- **Los contadores Quick Strike, hiperactividad y mensajes del servidor**, cuando el programa
  activo los define.
- **Las ventanas de noticias.** Los eventos restringidos se clasifican desde el calendario
  ForexFactory, y el panel muestra la cuenta atrás del próximo evento vinculante, con la parte del
  beneficio que tu programa conserva para una operación tomada dentro de esa ventana — incluidos
  los programas que no conservan ninguna.

**Lo que aconseja**

Un tamaño de lote, calculado desde tu riesgo por operación, tu distancia de stop y el margen que
realmente queda bajo el límite más cercano. Está acotado para que una operación perdedora no pueda
llevar la cuenta más allá de un límite, y cuando el resultado cae por debajo del mínimo del bróker
lo dice en lugar de mostrar un número inservible. La cifra está en un campo seleccionable: clic,
copia, pegado en la orden.

**Herramientas de disciplina**

Una escalera de bloqueos de tres peldaños. Tu **autobloqueo**, armado con dos clics y liberado con
otros dos — un pacto del que no se puede salir es una trampa, no disciplina. Un **bloqueo duro**
cuando la pérdida diaria alcanza el 80 % de su límite. Una **pausa** tras varias pérdidas
consecutivas. Además, la detección de tilt: demasiadas entradas dentro de tu ventana, o una
posición nueva mayor que tu última pérdida cerrada. Mientras un bloqueo está activo, los controles
que lo levantarían o que aflojarían un límite están desactivados — incluido el botón que quita la
herramienta del gráfico.

**Programas**

Un catálogo de perfiles integrado: FundedNext Stellar 1-Step, 2-Step, Lite e Instant, con sus
complementos. Se incluyen perfiles compatibles con los conjuntos de reglas de FTMO, E8, The5ers y
MyFundedFX. Cada límite mostrado se deriva del perfil elegido — cambia el perfil y todas las cifras
lo siguen.

**La interfaz**

Un raíl de 36 píxeles en el borde derecho del gráfico, una celda por dominio, cada una con un
micro-estado en vivo. Un clic en una celda abre un panel delante de ella. Un galón apila todas las
secciones en una barra lateral completa. La barra superior lleva las tres cifras que deciden el
siguiente clic: margen hasta el límite más cercano, lote aconsejado, próxima noticia. Una tabla
flotante lista las posiciones abiertas con su antigüedad, su P&L y la falta de stop.

**Manual integrado**

La sección AYUDA es la documentación: una guía de uso paso a paso y después un desplegable por
superficie y por sección, que enumera cada elemento con su significado. Nada que leer en otro sitio
antes de usar la herramienta.

**De solo lectura, por construcción**

El indicador no contiene ninguna función de trading. No puede enviar una orden ni modificarla. Las
alertas sonoras se disparan en los cambios de estado, con los archivos que elijas.

**Interfaz en inglés, francés y español.**

**Instalación.** Adjunta el indicador a un gráfico. Para la clasificación de noticias de
ForexFactory, añade también el servicio `RCNewsFeeder` desde el Navegador y autoriza la URL del
calendario en Herramientas → Opciones → Asesores Expertos. Sin el servicio, las reglas de noticias
recurren al calendario de MetaTrader, que clasifica los eventos de forma diferente; el panel indica
qué fuente se está usando.

**No se hace ninguna promesa de beneficio en este producto.** Mide reglas y distancias. Lo que
hagas con ellas es tu decisión.

---

## 📋 Champs du formulaire (rappel)

| Champ | Valeur |
|---|---|
| Titre | `RiskCockpit Prop Firm Risk Dashboard` (≤ 50 car., latin, pas de version, pas de mot tout-majuscule) |
| Version | `3.59` (format `major.minor`) |
| Catégorie | Indicateurs |
| Prix | Gratuit (inchangé) |
| Icône | `brand/RiskCockpit_logo_200.png` / `_140` / `_60` |
| Captures | `market/screens/` — 12 max, texte en **ANGLAIS**, 720 px min sur un côté, 1920×1080 max, ≤ 2 Mo |
| Vidéo | lien YouTube **non répertoriée**, un lien par langue |
