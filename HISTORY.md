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
| Build tree (MT5 data folder) | `%APPDATA%\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\` |
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
