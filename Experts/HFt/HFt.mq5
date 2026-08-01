//@version=6
// =====================================================================================
//  GOLD OPTIONS PROFILE (OGQ6)
//  Standalone companion to your sessions indicator. Draws a right-side open-interest
//  histogram (call/put split) at each strike, gamma-intensity caps, the pin & gamma
//  zones, connecting strike lines, and a live stats table.
//
//  Data is a manual snapshot from the CME OI heatmap + Vol2Vol (OGQ6, 18 DTE).
//  Update the arrays in the DATA section whenever you re-pull the heatmap.
//  Use on a GOLD chart (XAUUSD / GC). Overlay = true.
// =====================================================================================
indicator("Gold Options Profile (OGQ6)", overlay = true, max_boxes_count = 500, max_lines_count = 500, max_labels_count = 500)

// -------------------------------- Inputs --------------------------------
const string GRP = "Display"
bool   showHist   = input.bool(true,  "Show OI histogram (right side)", group = GRP)
bool   showLevels = input.bool(true,  "Show strike lines",             group = GRP)
bool   showZones  = input.bool(true,  "Shade zones (pin + corridor)",  group = GRP)
bool   showGamma  = input.bool(true,  "Gamma-intensity caps",          group = GRP)
bool   showTable  = input.bool(true,  "Show stats table",              group = GRP)
int    histWidth  = input.int(60,     "Histogram max width (bars)", minval = 10, group = GRP)
int    histGap    = input.int(8,      "Gap: price to histogram (bars)", minval = 0, group = GRP)
float  barHeight  = input.float(9,    "Bar height (price units)", minval = 1, group = GRP)
string labSizeIn  = input.string("Normal", "Label size", options = ["Small", "Normal", "Large", "Huge"], group = GRP)

const string ZGRP = "Zones"
float pinLow   = input.float(4085.773, "Pin zone - low",       group = ZGRP)
float pinHigh  = input.float(4117.576, "Pin zone - high",      group = ZGRP)
float corrLow  = input.float(4150,     "Gamma corridor - low", group = ZGRP)
float corrHigh = input.float(4300,     "Gamma corridor - high",group = ZGRP)

const string CGRP = "Colors"
color callCol  = input.color(#16a37f, "Call OI",  group = CGRP)
color putCol   = input.color(#e0813c, "Put OI",   group = CGRP)
color gammaCol = input.color(#8b5cf6, "Gamma",    group = CGRP)
color pinCol   = input.color(color.gray,   "Pin zone shade",      group = CGRP)
color corrCol  = input.color(color.purple, "Gamma corridor shade",group = CGRP)

string labSize = switch labSizeIn
    "Small"  => size.small
    "Normal" => size.normal
    "Large"  => size.large
    "Huge"   => size.huge
    => size.normal

// -------------------------------- DATA (edit on re-pull) --------------------------------
// strike, call OI, put OI, gamma(1-pt density 0-5), short role
var array<float>  strikes = array.from(4000., 4075., 4100., 4125., 4150., 4200., 4250., 4300., 4400.)
var array<float>  callOI  = array.from(60.,   256.,  1447., 592.,  2630., 2353., 2764., 3533., 4284.)
var array<float>  putOI   = array.from(4240., 790.,  2032., 388.,  2516., 1414., 1305., 1096., 200.)
var array<float>  gammaV  = array.from(1.,    0.,    4.,    1.,    5.,    4.,    5.,    5.,    2.)
var array<string> roles   = array.from("Floor", "Put shelf", "Put wall", "Flow", "PIN/gamma", "Anchor", "Call wall", "Trigger", "Far wall")

// -------------------------------- helpers --------------------------------
kfmt(float x) =>
    x >= 1000 ? str.tostring(x / 1000, "#.0") + "k" : str.tostring(x, "#")

// persistent drawing handles
var array<box>      hBoxes  = array.new<box>()
var array<line>     hLines  = array.new<line>()
var array<label>    hLabels = array.new<label>()
var array<line>     zLines  = array.new<line>()
var array<linefill> zFills  = array.new<linefill>()
var table statTbl = na

if barstate.islast
    // ---- clear previous ----
    for b in hBoxes
        box.delete(b)
    hBoxes.clear()
    for l in hLines
        line.delete(l)
    hLines.clear()
    for lb in hLabels
        label.delete(lb)
    hLabels.clear()
    for zl in zLines
        line.delete(zl)
    zLines.clear()
    for zf in zFills
        linefill.delete(zf)
    zFills.clear()

    int   n     = array.size(strikes)
    int   baseX = bar_index + histGap

    // scale by the largest total OI so the biggest wall = full width
    float maxTot = 0.0
    for i = 0 to n - 1
        maxTot := math.max(maxTot, array.get(callOI, i) + array.get(putOI, i))
    float scale = maxTot > 0 ? histWidth / maxTot : 0.0

    // ---- zone shades ----
    if showZones
        pzHi = line.new(bar_index - 1, pinHigh, bar_index, pinHigh, extend = extend.both, color = color.new(pinCol, 55), style = line.style_dotted, width = 1)
        pzLo = line.new(bar_index - 1, pinLow,  bar_index, pinLow,  extend = extend.both, color = color.new(pinCol, 55), style = line.style_dotted, width = 1)
        zLines.push(pzHi)
        zLines.push(pzLo)
        zFills.push(linefill.new(pzHi, pzLo, color.new(pinCol, 85)))

        hgHi = line.new(bar_index - 1, corrHigh, bar_index, corrHigh, extend = extend.both, color = color.new(corrCol, 55), style = line.style_dotted, width = 1)
        hgLo = line.new(bar_index - 1, corrLow,  bar_index, corrLow,  extend = extend.both, color = color.new(corrCol, 55), style = line.style_dotted, width = 1)
        zLines.push(hgHi)
        zLines.push(hgLo)
        zFills.push(linefill.new(hgHi, hgLo, color.new(corrCol, 90)))

    // ---- per-strike: connecting line, histogram bar (put+call), gamma cap, label ----
    for i = 0 to n - 1
        float s   = array.get(strikes, i)
        float cO  = array.get(callOI, i)
        float pO  = array.get(putOI, i)
        float g   = array.get(gammaV, i)
        string rl = array.get(roles, i)
        float tot = cO + pO
        bool  callDom = cO >= pO
        color domCol  = callDom ? callCol : putCol

        // connecting strike line across the chart
        if showLevels
            int w = tot > 4000 ? 3 : tot > 2000 ? 2 : 1
            ln = line.new(bar_index - 1, s, bar_index, s, extend = extend.both, color = color.new(domCol, 35), style = line.style_solid, width = w)
            hLines.push(ln)

        // histogram bar: put segment then call segment (total length = total OI)
        if showHist
            float pLen = pO * scale
            float cLen = cO * scale
            float top  = s + barHeight / 2
            float bot  = s - barHeight / 2
            pBox = box.new(baseX, top, int(math.round(baseX + pLen)), bot, border_color = na, bgcolor = color.new(putCol, 15))
            cBox = box.new(int(math.round(baseX + pLen)), top, int(math.round(baseX + pLen + cLen)), bot, border_color = na, bgcolor = color.new(callCol, 15))
            hBoxes.push(pBox)
            hBoxes.push(cBox)

            // gamma-intensity cap at the far end (more opaque = higher gamma)
            if showGamma and g > 0
                int   capX = int(math.round(baseX + pLen + cLen))
                int   gtr  = int(math.max(5, 90 - g * 16))
                gBox = box.new(capX, top, capX + 2, bot, border_color = na, bgcolor = color.new(gammaCol, gtr))
                hBoxes.push(gBox)

            // row label sitting just left of the histogram baseline
            string txt = str.tostring(s, "#") + "  " + rl + "\n" + kfmt(pO) + "P / " + kfmt(cO) + "C   γ" + str.tostring(g, "#")
            lb = label.new(baseX - 1, s, txt, style = label.style_label_right, textalign = text.align_right, textcolor = domCol, color = color.new(color.black, 100), size = labSize)
            hLabels.push(lb)

    // ---- stats table ----
    if showTable
        float price  = close
        float nearUp = na
        float nearDn = na
        for i = 0 to n - 1
            float s = array.get(strikes, i)
            if s >= price and (na(nearUp) or s < nearUp)
                nearUp := s
            if s <= price and (na(nearDn) or s > nearDn)
                nearDn := s
        bool inPin = price >= pinLow and price <= pinHigh

        if na(statTbl)
            statTbl := table.new(position.top_right, 2, 6, border_width = 1, border_color = color.new(color.gray, 50), frame_width = 1, frame_color = color.new(color.gray, 50))
        table.cell(statTbl, 0, 0, "OGQ6 · 18 DTE", text_color = color.white, bgcolor = color.new(color.black, 15), text_size = size.small, text_halign = text.align_left)
        table.cell(statTbl, 1, 0, "snapshot",      text_color = color.new(color.white, 30), bgcolor = color.new(color.black, 15), text_size = size.small, text_halign = text.align_right)
        table.cell(statTbl, 0, 1, "Spot",   text_color = color.white, text_size = size.small, text_halign = text.align_left)
        table.cell(statTbl, 1, 1, str.tostring(price, format.mintick), text_color = color.white, text_size = size.small, text_halign = text.align_right)
        table.cell(statTbl, 0, 2, "Wall ↑", text_color = callCol, text_size = size.small, text_halign = text.align_left)
        table.cell(statTbl, 1, 2, na(nearUp) ? "—" : str.tostring(nearUp, "#") + "  (+" + str.tostring(nearUp - price, "#") + ")", text_color = callCol, text_size = size.small, text_halign = text.align_right)
        table.cell(statTbl, 0, 3, "Wall ↓", text_color = putCol, text_size = size.small, text_halign = text.align_left)
        table.cell(statTbl, 1, 3, na(nearDn) ? "—" : str.tostring(nearDn, "#") + "  (−" + str.tostring(price - nearDn, "#") + ")", text_color = putCol, text_size = size.small, text_halign = text.align_right)
        table.cell(statTbl, 0, 4, "Pin zone", text_color = color.white, text_size = size.small, text_halign = text.align_left)
        table.cell(statTbl, 1, 4, inPin ? "INSIDE" : "outside", text_color = inPin ? color.yellow : color.new(color.white, 30), text_size = size.small, text_halign = text.align_right)
        table.cell(statTbl, 0, 5, "Max OI", text_color = color.white, text_size = size.small, text_halign = text.align_left)
        table.cell(statTbl, 1, 5, "4300 · 3.5kC", text_color = callCol, text_size = size.small, text_halign = text.align_right)