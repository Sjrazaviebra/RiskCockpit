//+------------------------------------------------------------------+
//|                                                  JR_CanvasUI.mqh  |
//|   Reusable modern-UI canvas kit for JR / "The Solution Maker".    |
//|                                                                  |
//|   The shared VISUAL LANGUAGE of the product family (RiskCockpit,  |
//|   StrategyDeck, ProSessionBox...) : one CCanvas ARGB bitmap draws |
//|   rounded cards, soft vertical gradients, layered drop shadows,   |
//|   hairline separators, rounded-end meters, pill toggles, segment  |
//|   controls and flat buttons. Products keep TEXT as OBJ_LABEL and  |
//|   CLICK TARGETS as transparent OBJ_BUTTONs on top.                |
//|                                                                  |
//|   Design tokens live in UITheme (fill with UIThemeDark()); every  |
//|   primitive takes explicit colors so a product can theme freely.  |
//|   Self-contained : depends only on <Canvas\Canvas.mqh>.           |
//+------------------------------------------------------------------+
#ifndef __JR_CANVAS_UI_MQH__
#define __JR_CANVAS_UI_MQH__

#include <Canvas\Canvas.mqh>

//--- Brand design tokens (RGB via C'r,g,b'; alpha applied per-call). --------
struct UITheme {
   color bg_deep, bg_top, bg_bot;   // panel body gradient (top -> bottom) + deepest
   color card_top, card_bot;        // card gradient
   color raise;                     // hovered / raised control
   color line, line_hi;             // hairline / stronger divider
   color txt, label, dim;           // text tiers
   color accent, accent_deep;       // primary (cyan) + its deep end
   color ok, warn, red;             // semantic (safe / watch / breach)
   int   radius_panel, radius_card, radius_ctrl;
};

void UIThemeDark(UITheme &t) {
   t.bg_deep = C'8,12,20';    t.bg_top = C'20,29,49';  t.bg_bot = C'13,20,36';
   t.card_top = C'27,39,64';  t.card_bot = C'22,32,52';
   t.raise = C'34,48,78';
   t.line = C'51,65,85';      t.line_hi = C'71,90,120';
   t.txt = C'232,238,247';    t.label = C'142,163,192';  t.dim = C'95,112,140';
   t.accent = C'56,189,248';  t.accent_deep = C'14,116,144';
   t.ok = C'52,211,153';      t.warn = C'251,191,36';    t.red = C'248,113,113';
   t.radius_panel = 14;       t.radius_card = 11;        t.radius_ctrl = 8;
}

//+------------------------------------------------------------------+
//| CCanvasKit : thin wrapper over CCanvas with modern primitives.   |
//| Coordinates are LOCAL to the bitmap (0,0 = top-left of the kit).  |
//+------------------------------------------------------------------+
class CCanvasKit {
private:
   CCanvas m_cv;
   bool    m_ready;
   int     m_w, m_h;

   uint A(const color c, const uchar a = 0xFF) const { return ColorToARGB(c, a); }
   uint Lerp(const uint x, const uint y, double t) const {
      if(t < 0.0) t = 0.0; if(t > 1.0) t = 1.0;
      uchar xa=(uchar)(x>>24), xr=(uchar)(x>>16), xg=(uchar)(x>>8), xb=(uchar)x;
      uchar ya=(uchar)(y>>24), yr=(uchar)(y>>16), yg=(uchar)(y>>8), yb=(uchar)y;
      uchar ra=(uchar)(xa+(ya-xa)*t), rr=(uchar)(xr+(yr-xr)*t),
            rg=(uchar)(xg+(yg-xg)*t), rb=(uchar)(xb+(yb-xb)*t);
      return((uint)ra<<24)|((uint)rr<<16)|((uint)rg<<8)|(uint)rb;
   }

public:
   void Init(void) { m_ready = false; m_w = 0; m_h = 0; }
   bool Ready(void) const { return m_ready; }
   int  W(void) const { return m_w; }
   int  H(void) const { return m_h; }

   //--- lifecycle : one bitmap-label object named `name` at (x,y). ----------
   bool Create(const string name, const int x, const int y, const int w, const int h) {
      if(m_ready) m_cv.Destroy();
      m_w = w; m_h = h;
      m_ready = m_cv.CreateBitmapLabel(0, 0, name, x, y, w, h, COLOR_FORMAT_ARGB_NORMALIZE);
      if(m_ready) {
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_ZORDER, 0); // clicks pass to controls on top
      }
      return m_ready;
   }
   void Destroy(void) { if(m_ready) { m_cv.Destroy(); m_ready = false; } }
   void Begin(void)   { if(m_ready) m_cv.Erase(ColorToARGB(clrBlack, 0)); } // clear transparent
   void Commit(void)  { if(m_ready) m_cv.Update(true); }

   //--- filled rounded rectangle (2 rects + 4 corner discs). ----------------
   void RoundFill(const int x, const int y, const int w, const int h, int r, const uint argb) {
      if(!m_ready) return;
      if(r > w/2) r = w/2; if(r > h/2) r = h/2; if(r < 0) r = 0;
      m_cv.FillRectangle(x+r, y, x+w-1-r, y+h-1, argb);
      m_cv.FillRectangle(x, y+r, x+w-1, y+h-1-r, argb);
      m_cv.FillCircle(x+r,       y+r,       r, argb);
      m_cv.FillCircle(x+w-1-r,   y+r,       r, argb);
      m_cv.FillCircle(x+r,       y+h-1-r,   r, argb);
      m_cv.FillCircle(x+w-1-r,   y+h-1-r,   r, argb);
   }

   //--- 1px (or `th`px) rounded border : filled ring = outer fill minus inner.
   void RoundStroke(const int x, const int y, const int w, const int h, const int r,
                    const uint argb, const int th = 1) {
      if(!m_ready) return;
      RoundFill(x, y, w, h, r, argb);
      // punch a transparent-composited hole is not possible after fill, so the
      // caller draws the interior AFTER this (Card does exactly that).
   }

   //--- soft drop shadow : `layers` translucent rounded rects growing outward.
   void SoftShadow(const int x, const int y, const int w, const int h, const int r,
                   const color base, const int spread = 8, const uchar peak = 90) {
      if(!m_ready) return;
      for(int i = spread; i >= 1; --i) {
         const uchar a = (uchar)(peak * (double)(spread - i + 1) / (double)spread / 2.0);
         RoundFill(x - i, y - i + 2, w + 2*i, h + 2*i, r + i, A(base, a));
      }
   }

   //--- idle edge glow : concentric translucent outlines OUTSIDE the card edge, ---
   //--- brightest hugging the edge, fading outward (mockup .rc::after cyan halo). ---
   //--- Draw AFTER SoftShadow and BEFORE Card : the opaque Card overwrites the    ---
   //--- interior, leaving only the 1px ring fringes visible in the margin band.   ---
   void EdgeGlow(const int x, const int y, const int w, const int h, const int r,
                 const color base, const int spread = 6, const uchar peak = 46) {
      if(!m_ready) return;
      for(int i = spread; i >= 1; --i) {
         const uchar a = (uchar)(peak * (double)(spread - i + 1) / (double)spread / 2.0);
         RoundFill(x - i, y - i, w + 2*i, h + 2*i, r + i, A(base, a));
      }
   }

   //--- vertical gradient band : rounded TOP cap (base = top colour), banded lerp --
   //--- top->bot over the body, square bottom (for title/footer bands whose lower --
   //--- edge continues into the next section). Pass PRE-BLENDED opaque colours :   --
   //--- CCanvas draws overwrite pixels (no compositing), so translucent fills over --
   //--- the card would show the CHART through, not the card.                       --
   void GradientVFill(const int x, const int y, const int w, const int h, int r,
                      const uint top, const uint bot) {
      if(!m_ready) return;
      if(r > w/2) r = w/2; if(r > h/2) r = h/2; if(r < 0) r = 0;
      RoundFill(x, y, w, h, r, top); // base incl. the rounded top cap
      const int gy0 = y + r, gy1 = y + h, bands = 16;
      if(gy1 > gy0) {
         const int bh = MathMax(1, (gy1 - gy0) / bands);
         for(int b = 0; b*bh < (gy1 - gy0); ++b) {
            const uint c = Lerp(top, bot, (double)(b*bh) / (double)(gy1 - gy0));
            m_cv.FillRectangle(x, gy0 + b*bh, x + w - 1, MathMin(gy1 - 1, gy0 + (b+1)*bh), c);
         }
      }
   }

   //--- vertical gradient band : SQUARE top, ROUNDED BOTTOM corners - for the LAST  --
   //--- band of a card (a square fill there covers the card's bottom rounding).     --
   //--- Scanline rows : full width until the bottom r rows, then clipped to the     --
   //--- corner chord (same math as Capsule). The corner notches are NEVER painted,  --
   //--- so whatever sits there (shadow / glow / chart) stays intact.                --
   void GradientVFillB(const int x, const int y, const int w, const int h, int r,
                       const uint top, const uint bot) {
      if(!m_ready || w <= 0 || h <= 0) return;
      if(r > w/2) r = w/2; if(r > h/2) r = h/2; if(r < 0) r = 0;
      const double cxL = x + r, cxR = x + w - r; // bottom corner-circle centres (x)
      for(int row = 0; row < h; ++row) {
         const uint c = Lerp(top, bot, (double)row / (double)h);
         int xl = x, xr = x + w - 1;
         const double dyc = (row + 0.5) - (double)(h - r); // >0 = inside the rounding
         if(dyc > 0.0) {
            const double s  = (double)r*r - dyc*dyc;
            const double hw = (s > 0.0 ? MathSqrt(s) : 0.0);
            xl = (int)MathRound(cxL - hw);
            xr = (int)MathRound(cxR + hw) - 1;
            if(xl < x) xl = x; if(xr > x + w - 1) xr = x + w - 1;
         }
         if(xr >= xl) m_cv.FillRectangle(xl, y + row, xr, y + row, c);
      }
   }

   //--- card : border ring + vertical gradient interior + faint top sheen. --
   void Card(const int x, const int y, const int w, const int h, const int r,
             const color top, const color bot, const color border) {
      if(!m_ready) return;
      RoundFill(x, y, w, h, r, A(border));                     // border ring
      const int ix = x+1, iy = y+1, iw = w-2, ih = h-2, ir = (r>0?r-1:0);
      // rounded interior base (bottom colour), then gradient bands over the
      // straight-sided middle (cheap ; corners keep the base tone).
      RoundFill(ix, iy, iw, ih, ir, A(bot));
      const int gy0 = iy + ir, gy1 = iy + ih - ir, bands = 22;
      if(gy1 > gy0) {
         const int bh = MathMax(1, (gy1 - gy0) / bands);
         for(int b = 0; b*bh < (gy1 - gy0); ++b) {
            const uint c = Lerp(A(top), A(bot), (double)(b*bh) / (double)(gy1 - gy0));
            m_cv.FillRectangle(ix, gy0 + b*bh, ix + iw - 1, MathMin(gy1, gy0 + (b+1)*bh), c);
         }
      }
      // top sheen : OPAQUE pre-blend (CCanvas draws overwrite pixels - a translucent
      // strip INSIDE the card would show the chart through wherever nothing opaque
      // sits beneath the bitmap ; Button() inherits this line on every face).
      m_cv.FillRectangle(ix + ir, iy + 1, ix + iw - 1 - ir, iy + 2, Lerp(A(top), A(clrWhite), 0.055));
   }

   void Hairline(const int x1, const int y, const int x2, const color c, const uchar a = 255) {
      if(m_ready) m_cv.Line(x1, y, x2, y, A(c, a));
   }

   //--- rounded-end meter : track + gradient fill clipped to `ratio` (0..1). -
   void Meter(const int x, const int y, const int w, const int h, double ratio,
              const color track, const color fillA, const color fillB) {
      if(!m_ready) return;
      if(ratio < 0.0) ratio = 0.0; if(ratio > 1.0) ratio = 1.0;
      const int r = h/2;
      Capsule(x, y, w, h, A(track));   // CAPSULE REWRITE : clean pill ends
      const int fw = (int)MathRound(w * ratio);
      if(fw >= 2) {
         Capsule(x, y, fw, h, A(fillA)); // Capsule self-clamps r=min(h/2, fw/2) when fw<h
         // subtle left->right gradient on the straight middle of the fill
         const int gx0 = x + r, gx1 = x + fw - r, bands = 16;
         if(gx1 > gx0) {
            const int bw = MathMax(1, (gx1 - gx0)/bands);
            for(int b = 0; b*bw < (gx1 - gx0); ++b) {
               const uint c = Lerp(A(fillA), A(fillB), (double)(b*bw)/(double)(gx1 - gx0));
               m_cv.FillRectangle(gx0 + b*bw, y + 1, MathMin(gx1, gx0 + (b+1)*bw), y + h - 2, c);
            }
         }
      }
   }

   //--- pill toggle : track + sliding knob (knob pos eased by the caller). ---
   void PillToggle(const int x, const int y, const int w, const int h, const bool on,
                   const color offTrack, const color onA, const color onB,
                   const color knob, double knobT = -1.0) {
      if(!m_ready) return;
      const int r = h/2;
      if(on) {
         // v2.01 RELIEF : vertical light->dark gradient (onB = bright accent on top,
         // onA = deep end at the bottom) = same relief language as Segment/Card.
         CapsuleGradient(x, y, w, h, A(onB), A(onA));
      } else {
         Capsule(x, y, w, h, A(offTrack)); // OFF = flat recessed film (mockup .sw track)
      }
      const double t = (knobT >= 0.0 ? knobT : (on ? 1.0 : 0.0));
      const int kr = r - 2;
      const int kx = (int)(x + r + t * (w - 2*r));
      // knob DROP shadow (offset down, mockup 0 2px 4px) : OPAQUE pre-blend against the
      // track tone - a translucent circle inside the card would chart-through (overwrite).
      // v2.01 : blends against onA = the LOWER gradient tone, where the shadow sits.
      const uint sh = Lerp(A(on ? onA : offTrack), A(clrBlack), 0.30);
      m_cv.FillCircle(kx, y + r + 1, kr + 1, sh);
      m_cv.FillCircle(kx, y + r, kr, A(knob));
   }

   //--- flat button face : gradient body + border ; states via colours. -----
   void Button(const int x, const int y, const int w, const int h, const int r,
               const color top, const color bot, const color border) {
      Card(x, y, w, h, r, top, bot, border);
   }

   //--- one segment of a segmented control (active = filled accent). --------
   void Segment(const int x, const int y, const int w, const int h, const int r,
                const bool active, const color fillA, const color fillB, const color idle) {
      if(!m_ready) return;
      if(active) {
         // v2.01 RELIEF : gradient capsule (scanline = clean pill ends, PLUS the
         // vertical fillA->fillB relief the old gradient face had).
         CapsuleGradient(x, y, w, h, A(fillA), A(fillB));
      } else {
         Capsule(x, y, w, h, A(idle));
      }
   }

   //--- Capsule pleine, bouts arrondis parfaits, hauteur EXACTE h (0 debordement). ---
   //--- SCANLINES : chaque rangee = sa demi-corde exacte, inscrite dans la boite h  ---
   //--- -> flancs a ras, demi-cercles tangents. (RoundFill @ r=h/2 bombait de 1-2px ---
   //--- aux bouts = l'"os de chien" ; ce primitif le remplace pour les pilules.)    ---
   void Capsule(const int x, const int y, const int w, const int h, const uint argb) {
      if(!m_ready || w <= 0 || h <= 0) return;
      double r = h / 2.0;                 if(r > w / 2.0) r = w / 2.0;
      double cxL = x + r, cxR = x + w - r, cy = h / 2.0;
      for(int row = 0; row < h; ++row) {
         double dyc = (row + 0.5) - cy;
         double s   = r*r - dyc*dyc;
         double hw  = (s > 0.0 ? MathSqrt(s) : 0.0);
         int xl = (int)MathRound(cxL - hw);
         int xr = (int)MathRound(cxR + hw) - 1;
         if(xl < x) xl = x; if(xr > x + w - 1) xr = x + w - 1;
         if(xr >= xl) m_cv.FillRectangle(xl, y + row, xr, y + row, argb);
      }
   }
   //--- Anneau capsule d'epaisseur UNIFORME (ring puis interieur inset th). ---------
   void CapsuleStroke(const int x, const int y, const int w, const int h,
                      const uint ring, const uint inner, const int th = 1) {
      if(!m_ready || w <= 0 || h <= 0) return;
      Capsule(x, y, w, h, ring);
      const int t = (th < 1 ? 1 : th);
      if(w - 2*t > 0 && h - 2*t > 0) Capsule(x + t, y + t, w - 2*t, h - 2*t, inner);
   }
   //--- Capsule avec RELIEF 3D : meme trace scanline que Capsule() (zero os-de-chien) ---
   //--- mais chaque rangee est teintee Lerp(top,bot, row/h) -> pilule bombee, haut    ---
   //--- clair -> bas fonce. C'est le MEME langage de relief que Card/Button (gradient ---
   //--- vertical raise->surface / accent->accent_deep) : une seule famille de formes. ---
   void CapsuleGradient(const int x, const int y, const int w, const int h,
                        const uint top, const uint bot) {
      if(!m_ready || w <= 0 || h <= 0) return;
      double r = h / 2.0;                 if(r > w / 2.0) r = w / 2.0;
      double cxL = x + r, cxR = x + w - r, cy = h / 2.0;
      const double dn = (h > 1 ? (double)(h - 1) : 1.0); // last row = bot exactly
      for(int row = 0; row < h; ++row) {
         double dyc = (row + 0.5) - cy;
         double s   = r*r - dyc*dyc;
         double hw  = (s > 0.0 ? MathSqrt(s) : 0.0);
         int xl = (int)MathRound(cxL - hw);
         int xr = (int)MathRound(cxR + hw) - 1;
         if(xl < x) xl = x; if(xr > x + w - 1) xr = x + w - 1;
         if(xr >= xl) m_cv.FillRectangle(xl, y + row, xr, y + row,
                                         Lerp(top, bot, (double)row / dn));
      }
   }
};

#endif // __JR_CANVAS_UI_MQH__
