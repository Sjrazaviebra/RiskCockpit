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
