"""Masar identity — one monoline, octilinear system (0°/45°/90°), round caps and joins.

The idea: the Arabic word مسار is drawn as a metro line.
  م  = a station ring with a gold "arrival" dot (also the initial of مترو)
  س  = three station ticks on the track
  ا  = a tall mast
  ر  = a 45° branch line
The app symbol is the same ring at an interchange: a white leg rises at 45°,
changes at the ring, and leaves on a gold leg — "ride, change, arrive".
Ring radius : stroke = 1.43 in both the wordmark and the symbol; gold dot = 0.42 × ring radius.
"""
GREEN="#00795C"; GREEN_HI="#0A8E6C"; GREEN_LO="#006A50"
GOLD="#F6B53C"; NIGHT="#0B1A22"; MIST="#EEF3F1"; WHITE="#FFFFFF"

def wordmark_paths(color="currentColor", dot=GOLD, s=14):
    """مسار in a 0 0 300 150 box (baseline y=100). Returns inner SVG."""
    r=20; B=100; cx=262; ax=cx-118; rx=ax-28
    st=f'fill="none" stroke="{color}" stroke-width="{s}" stroke-linecap="round" stroke-linejoin="round"'
    d=f'M{cx} {B} H{ax} V{B-92}'
    for t in (cx-42, cx-64, cx-86): d+=f' M{t} {B} V{B-24}'
    out=[f'<circle cx="{cx}" cy="{B-r}" r="{r}" {st}/>', f'<path d="{d}" {st}/>',
         f'<path d="M{rx} {B-18} V{B} L{rx-34} {B+34}" {st}/>']
    if dot: out.append(f'<circle cx="{cx}" cy="{B-r}" r="{r*0.42:.1f}" fill="{dot}"/>')
    return "".join(out)

WM_VIEWBOX="78 -7 213 158"   # tight box around the drawn word incl. stroke

def wordmark_svg(color=NIGHT, dot=GOLD, height=158):
    w=round(213*height/158)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{WM_VIEWBOX}" width="{w}" height="{height}" role="img" aria-label="مسار Masar">{wordmark_paths(color,dot)}</svg>'

def symbol_paths(leg1=WHITE, leg2=GOLD, ring=WHITE, dot=GOLD, hole=GREEN, S=1024):
    k=S/1024; s=90*k; R=128*k; c=512*k; d=236*k
    st=lambda col: f'fill="none" stroke="{col}" stroke-width="{s:.1f}" stroke-linecap="round" stroke-linejoin="round"'
    e=R*0.7071   # legs stop on the ring's centreline so nothing shows through the hole
    out=[f'<path d="M{-60*k:.1f} {c+d:.1f} H{c-d:.1f} L{c-e:.1f} {c+e:.1f}" {st(leg1)}/>',
         f'<path d="M{c+e:.1f} {c-e:.1f} L{c+d:.1f} {c-d:.1f} H{S+60*k:.1f}" {st(leg2)}/>',
         f'<circle cx="{c:.1f}" cy="{c:.1f}" r="{R:.1f}" fill="{hole}" stroke="{ring}" stroke-width="{s:.1f}"/>' if hole!="none"
         else f'<circle cx="{c:.1f}" cy="{c:.1f}" r="{R:.1f}" {st(ring)}/>',
         f'<circle cx="{c:.1f}" cy="{c:.1f}" r="{R*0.42:.1f}" fill="{dot}"/>']
    return "".join(out)

def icon_svg(kind="light", S=1024, radius=0):
    """kind: light (store icon), dark (iOS dark, transparent), tinted (iOS tinted, grayscale, transparent), mono-night."""
    clip=f' clip-path="url(#r)"' if radius else ""
    defs=f'<defs><clipPath id="r"><rect width="{S}" height="{S}" rx="{radius}"/></clipPath>'
    if kind=="light":
        defs+=f'<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{GREEN_HI}"/><stop offset="1" stop-color="{GREEN_LO}"/></linearGradient></defs>'
        body=f'<rect width="{S}" height="{S}" fill="url(#g)"/>'+symbol_paths(S=S, hole=GREEN)
    elif kind=="dark":
        defs+='</defs>'
        body=symbol_paths(leg1="#E8F5F0", leg2=GOLD, ring="#E8F5F0", dot=GOLD, hole="none", S=S)
    elif kind=="tinted":
        defs+='</defs>'
        body=symbol_paths(leg1="#B8B8B8", leg2="#FFFFFF", ring="#FFFFFF", dot="#FFFFFF", hole="none", S=S)
    elif kind=="night":
        defs+='</defs>'
        body=f'<rect width="{S}" height="{S}" fill="{NIGHT}"/>'+symbol_paths(S=S, hole=NIGHT)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">{defs}<g{clip}>{body}</g></svg>'
