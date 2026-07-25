#!/usr/bin/env python3
"""
Pixel-art sprite generator for the desktop cat.

Draws a slim black cat (Oriental/Thai type: tall pointed ears, long whippy
tail, amber eyes, little bell collar) as parametric pixel art, then runs three
post-passes that make it read on any wallpaper:

  * warm pass    -- scatters a few brown pixels; black cats are never flat black
  * rim pass     -- lights the top/back edge so he is visible on a black desktop
  * outline pass -- grows a 1px near-black border around the finished silhouette

Pass order matters: the rim is computed against the *original* silhouette, so
"is there sky above me" is asked before the outline surrounds everything.

Outputs one horizontal sheet per animation into Resources/Sprites, plus
sprites.json (frame counts + timings), plus a preview contact sheet.
"""

import json
import math
import os
from PIL import Image

W, H = 40, 32          # frame canvas
GROUND = 28.0          # y of the floor line

# ---------------------------------------------------------------- palette ---
OUTLINE    = (9, 9, 13, 255)
DARK       = (25, 25, 31, 255)     # far side of the body, in shadow
MID        = (37, 37, 46, 255)     # base fur
LIGHT      = (52, 52, 64, 255)     # muzzle, raised paw
RIM        = (110, 114, 138, 255)  # cool sheen along the back
WARM       = (66, 50, 40, 255)     # warm brown sheen, as in the photos
EYE        = (222, 198, 78, 255)
EYE_DK     = (156, 132, 44, 255)
PUPIL      = (13, 13, 17, 255)
INNER_EAR  = (84, 52, 62, 255)
NOSE       = (112, 62, 74, 255)
WHISKER    = (96, 100, 114, 255)
PINK       = (216, 116, 132, 255)
COLLAR     = (46, 40, 64, 255)     # key colour, remapped by the app
BELL       = (206, 176, 88, 255)   # key colour, remapped by the app
BANDANA    = (180, 72, 72, 255)    # key colour for the bandana cloth
TONGUE     = (214, 108, 120, 255)  # dog pant tongue
SPECIES    = "cat"                 # cat | dog -- set by main() per sheet set

# Cream Pomeranian palette, swapped in for the dog generation pass.
_CAT_PAL = {}
DOG_PAL = {
    "OUTLINE": (70, 52, 40, 255),
    "DARK":    (196, 168, 128, 255),
    "MID":     (224, 200, 160, 255),
    "LIGHT":   (242, 226, 196, 255),
    "RIM":     (252, 244, 228, 255),
    "WARM":    (210, 172, 126, 255),
    "EYE":     (52, 40, 32, 255),      # dark Pom eyes
    "EYE_DK":  (34, 26, 20, 255),
    "PUPIL":   (16, 12, 10, 255),
    "INNER_EAR": (214, 156, 150, 255),
    "NOSE":    (36, 30, 30, 255),      # black button nose
    "WHISKER": (232, 216, 190, 255),
    "PINK":    (224, 122, 134, 255),
    "MOUTH":   (74, 40, 40, 255),
}

def _use_palette(pal):
    g = globals()
    for k, v in pal.items():
        g[k] = v
MOUTH      = (28, 16, 20, 255)     # open mouth interior, for yawns
STAR       = (232, 214, 130, 255)  # the birdies circling a dazed cat
HEART_C    = (226, 92, 116, 255)   # love
ANGER      = (214, 96, 78, 255)    # the cross vein when annoyed
QUESTION   = (198, 204, 218, 255)  # curious
SWEAT      = (120, 178, 214, 255)  # surprise / nervous drop

PROTECT = {EYE, EYE_DK, PUPIL, WHISKER, PINK, INNER_EAR, NOSE, BELL, OUTLINE, MOUTH, STAR, HEART_C, ANGER, QUESTION, SWEAT, COLLAR, BANDANA}


class Canvas:
    def __init__(self, w=W, h=H):
        self.w, self.h = w, h
        self.px = {}
        self.late = []          # painted after outline_pass, so it stays hairline

    def put(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if c is None or x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        self.px[(x, y)] = c

    def put_late(self, x, y, c):
        self.late.append((int(round(x)), int(round(y)), c))

    def ellipse(self, cx, cy, rx, ry, c):
        if rx <= 0 or ry <= 0:
            return
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                dx, dy = (x - cx) / rx, (y - cy) / ry
                if dx * dx + dy * dy <= 1.0:
                    self.put(x, y, c)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(round(min(y0, y1))), int(round(max(y0, y1))) + 1):
            for x in range(int(round(min(x0, x1))), int(round(max(x0, x1))) + 1):
                self.put(x, y, c)

    def taper(self, x0, y0, x1, y1, w0, w1, c):
        steps = max(2, int(math.hypot(x1 - x0, y1 - y0) * 3))
        for i in range(steps + 1):
            t = i / steps
            r = (w0 + (w1 - w0) * t) / 2.0
            self.ellipse(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r, r, c)

    def poly(self, pts, c):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for i in range(len(pts)):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % len(pts)]
                if y0 != y1 and min(y0, y1) <= y < max(y0, y1):
                    xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(math.floor(xs[i])), int(math.ceil(xs[i + 1])) + 1):
                    self.put(x, y, c)

    def to_image(self):
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        p = img.load()
        for (x, y), c in self.px.items():
            p[x, y] = c
        return img


# ------------------------------------------------------------- post passes --

def warm_pass(cv):
    """A sparse warm scatter. Kept thin -- dense reads as tabby spots, not sheen."""
    for (x, y), c in list(cv.px.items()):
        if c == MID and ((x * 13 + y * 29) % 41) < 2:
            cv.put(x, y, WARM)


def rim_pass(cv):
    """Light the sky-facing edge. Runs BEFORE outline_pass by design.

    Requires solid fur directly below, so 1-2px limbs (tail, legs, whiskers)
    don't get lit end to end and read as bright wire.
    """
    solid = dict(cv.px)
    for (x, y), c in solid.items():
        if c in PROTECT or c == COLLAR:
            continue
        if (x, y + 1) not in solid:
            continue
        if (x, y - 1) not in solid:
            cv.put(x, y, RIM)
        elif (x - 1, y - 1) not in solid and (x - 1, y) not in solid:
            cv.put(x, y, LIGHT)


def fluff_pass(cv):
    """Adds a bumpy, furry fringe around the silhouette so the dog reads fluffy.
    Deterministic (hashed by position) so frames stay steady."""
    solid = dict(cv.px)
    fur = {DARK, MID, LIGHT, RIM, WARM}
    add = []
    for (x, y), c in solid.items():
        if c not in fur:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nb = (x + dx, y + dy)
            if nb in solid:
                continue
            if ((x * 7 + y * 13 + dx * 5 + dy * 11) % 10) < 4:   # ~40% of edges sprout fluff
                add.append((nb, c))
    for (pos, c) in add:
        cv.put(pos[0], pos[1], c)


def outline_pass(cv):
    solid = set(cv.px.keys())
    edge = set()
    for (x, y) in solid:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            if (x + dx, y + dy) not in solid:
                edge.add((x + dx, y + dy))
    for p in edge:
        cv.put(p[0], p[1], OUTLINE)


# ------------------------------------------------------------ cat features --

def draw_ears(cv, hx, hy, tw=0.0, flat=0.0):
    """Tall pointed ears -- cats and (fluffy) Pomeranians both have them erect."""
    lift = 1.0 - flat
    far = [(hx - 4.8, hy - 2.2), (hx - 6.2 + tw, hy - 2.2 - 8.4 * lift), (hx - 0.8, hy - 4.4)]
    near = [(hx + 0.4, hy - 4.6), (hx + 2.6 + tw, hy - 3.0 - 9.0 * lift), (hx + 5.4, hy - 2.0)]
    cv.poly(far, DARK)
    cv.poly([(far[0][0] + 1.3, far[0][1] - 0.4),
             (far[1][0] + 1.1, far[1][1] + 2.8),
             (far[2][0] - 1.1, far[2][1] + 0.2)], INNER_EAR)
    return near


def draw_near_ear(cv, hx, hy, near):
    cv.poly(near, MID)
    cv.poly([(near[0][0] + 1.2, near[0][1] - 0.6),
             (near[1][0] + 0.1, near[1][1] + 3.0),
             (near[2][0] - 1.5, near[2][1] - 0.4)], INNER_EAR)


def draw_face(cv, hx, hy, eye=1.0, mouth=0, look=0.0, yawn=0.0):
    # muzzle wedge pushes forward off the skull
    cv.ellipse(hx + 3.9, hy + 2.0, 2.4, 1.9, LIGHT)
    if SPECIES == "dog":
        cv.ellipse(hx + 5.6, hy + 1.8, 1.4, 1.2, NOSE)     # round black button nose
    else:
        cv.put(hx + 5.6, hy + 1.3, NOSE)
        cv.put(hx + 5.6, hy + 2.1, NOSE)
        cv.put(hx + 5.0, hy + 1.3, NOSE)

    ex, ey = hx + 2.1 + look, hy - 0.2
    if eye <= -2:                                    # narrowed: a hard glare
        cv.rect(ex - 1.5, ey - 0.3, ex + 1, ey + 0.3, EYE)
        cv.put(ex + 0.4, ey, PUPIL)
        cv.put(ex - 1.6, ey - 1.0, OUTLINE)          # angled brow
        cv.put(ex - 0.8, ey - 1.2, OUTLINE)
    elif eye < 0:                                    # dazed: a little spiral
        cv.put(ex - 1, ey, EYE_DK)
        cv.put(ex + 1, ey, EYE_DK)
        cv.put(ex, ey - 1, EYE_DK)
        cv.put(ex, ey + 1, EYE)
        cv.put(ex, ey, EYE)
    elif eye > 0.55:                                 # open: almond, 3x3
        cv.rect(ex - 1, ey - 1, ex + 1, ey + 1, EYE)
        cv.put(ex - 1.5, ey, EYE)
        cv.put(ex - 1.5, ey - 1, OUTLINE)
        cv.put(ex + 1, ey - 1, EYE_DK)
        cv.put(ex - 1, ey + 1, EYE_DK)
        cv.rect(ex + 0.3, ey - 0.6, ex + 0.3, ey + 1, PUPIL)
    elif eye > 0.2:                                  # half-lidded
        cv.rect(ex - 1.5, ey + 0.2, ex + 1, ey + 0.7, EYE_DK)
        cv.rect(ex - 1.5, ey - 0.4, ex + 1, ey - 0.4, OUTLINE)
    else:                                            # shut / content
        cv.rect(ex - 1.5, ey + 0.2, ex + 0.6, ey + 0.2, OUTLINE)
        cv.put(ex + 1.2, ey - 0.4, OUTLINE)

    if SPECIES == "dog":
        if yawn > 0.05:
            cv.ellipse(hx + 4.8, hy + 3.4, 1.2 + yawn * 1.2, 0.8 + yawn * 1.6, MOUTH)
        elif mouth:                                  # panting -- little tongue out
            cv.ellipse(hx + 5.0, hy + 3.8, 1.0, 1.5, TONGUE)
        return
    if yawn > 0.05:                                  # jaw drops open
        w = 1.1 + yawn * 1.7
        h = 0.7 + yawn * 2.1
        cv.ellipse(hx + 4.6, hy + 3.0, w, h, MOUTH)
        if yawn > 0.45:
            cv.ellipse(hx + 4.4, hy + 3.6, w * 0.5, h * 0.42, PINK)
    elif mouth:
        cv.put(hx + 4.9, hy + 3.3, PINK)
        cv.put(hx + 5.5, hy + 3.3, PINK)

    for wy in (0.7, 2.6):        # sparse dotted whiskers -- contiguous reads as a bar
        for i in (2, 4):
            cv.put_late(hx + 5.6 + i, hy + wy + i * 0.24, WHISKER)


def draw_head(cv, hx, hy, eye=1.0, tw=0.0, mouth=0, look=0.0, flat=0.0, yawn=0.0):
    near = draw_ears(cv, hx, hy, tw, flat)
    cv.ellipse(hx, hy, 5.4, 4.9, MID)                # skull
    cv.ellipse(hx + 1.6, hy + 2.2, 4.4, 3.3, MID)    # cheeks / short muzzle mass
    draw_near_ear(cv, hx, hy, near)
    draw_face(cv, hx, hy, eye, mouth, look, yawn)


# Which accessory this render pass bakes in. Set by main() before each sheet.
ACC_STYLE = "bell"

def draw_collar(cv, x, y):
    """Draws the neckwear for the current ACC_STYLE at the collar anchor (x, y)."""
    style = ACC_STYLE
    if style == "none":
        return
    if style == "band":
        cv.rect(x - 2.4, y, x + 2.4, y + 0.6, COLLAR)
        return
    if style == "bell":
        cv.rect(x - 2.2, y, x + 2.2, y + 0.4, COLLAR)
        cv.put(x + 1.0, y + 1.4, BELL)
        cv.put(x + 1.8, y + 1.4, BELL)
        cv.put(x + 1.4, y + 2.0, BELL)
        return
    if style == "bowtie":
        cv.rect(x - 2.4, y, x + 2.4, y + 0.5, COLLAR)
        # two triangles meeting at a knot
        cv.poly([(x + 0.2, y + 0.8), (x - 2.6, y - 0.6), (x - 2.6, y + 2.4)], COLLAR)
        cv.poly([(x + 0.6, y + 0.8), (x + 3.4, y - 0.6), (x + 3.4, y + 2.4)], COLLAR)
        cv.put(x + 0.4, y + 1.2, BELL)          # knot catches the light
        return
    if style == "bandana":
        cv.rect(x - 2.4, y - 0.2, x + 2.8, y + 0.6, BANDANA)
        # kerchief hanging down at the throat
        cv.poly([(x - 1.4, y + 0.6), (x + 2.2, y + 0.6), (x + 0.4, y + 4.2)], BANDANA)
        cv.put(x + 0.4, y + 2.0, COLLAR)
        return


def draw_tail(cv, x0, y0, angle, curl, seg=7, length=1.9, w0=4.4, w1=2.3, c=None):
    if c is None:
        c = DARK                         # resolved now, so a swapped palette applies
    if SPECIES == "dog":                 # a Pom's fat fluffy tail curls up high
        angle += 1.15
        curl += 0.34
        w0 += 2.4; w1 += 2.2
        length -= 0.1
        seg += 1
    x, y, a = x0, y0, angle
    for i in range(seg):
        t = i / max(1, seg - 1)
        nx, ny = x + math.cos(a) * length, y - math.sin(a) * length
        cv.taper(x, y, nx, ny, w0 + (w1 - w0) * t, w0 + (w1 - w0) * min(1, t + 1 / seg), c)
        x, y, a = nx, ny, a + curl


def draw_leg(cv, hip, knee, foot, w, c):
    cv.taper(hip[0], hip[1], knee[0], knee[1], w, w * 0.82, c)
    cv.taper(knee[0], knee[1], foot[0], foot[1], w * 0.82, w * 0.72, c)
    cv.ellipse(foot[0] + 0.4, foot[1] - 0.2, 1.9, 1.3, c)


def make_legs(bx, by, phase, amp, ground=GROUND):
    """Diagonal gait. amp=0 stands still. Returns (far, near) leg triples."""
    hips = {                       # (dx, dy, phase offset)
        "bf": (-4.6, 2.0, math.pi),
        "ff": (4.2, 1.9, 0.0),
        "bn": (-3.0, 2.4, 0.0),
        "fn": (5.6, 2.2, math.pi),
    }
    out = {}
    for k, (dx, dy, po) in hips.items():
        hx, hy = bx + dx, by + dy
        ph = phase + po
        swing = math.sin(ph) * amp
        lift = max(0.0, math.cos(ph)) * amp * 0.72
        foot = (hx + swing, ground - lift)
        knee = (hx + swing * 0.3, (hy + foot[1]) / 2 + 0.7)
        out[k] = ((hx, hy), knee, foot)
    return [out["bf"], out["ff"]], [out["bn"], out["fn"]]


# ---------------------------------------------------------------- poses -----

def draw_emote(cv, hx, hy, kind, t=0.0):
    """A little feeling-icon above and ahead of the head."""
    ex, ey = hx + 5.5, hy - 8.5 - t * 1.2
    if kind == "love":
        for dx in (-0.5, 0.5):
            cv.put(ex + dx, ey, HEART_C)
        cv.put(ex, ey + 0.6, HEART_C); cv.put(ex, ey - 0.6, HEART_C)
        cv.put(ex - 1, ey - 0.4, HEART_C); cv.put(ex + 1, ey - 0.4, HEART_C)
    elif kind == "anger":
        # the four-spoke manga cross-vein
        cv.put(ex, ey, ANGER); cv.put(ex + 1.4, ey, ANGER); cv.put(ex - 1.4, ey, ANGER)
        cv.put(ex + 0.7, ey - 1.0, ANGER); cv.put(ex - 0.7, ey - 1.0, ANGER)
        cv.put(ex + 0.7, ey + 1.0, ANGER); cv.put(ex - 0.7, ey + 1.0, ANGER)
    elif kind == "question":
        cv.put(ex, ey - 1.4, QUESTION); cv.put(ex + 1, ey - 1.4, QUESTION)
        cv.put(ex + 1.4, ey - 0.4, QUESTION); cv.put(ex + 0.6, ey + 0.4, QUESTION)
        cv.put(ex + 0.4, ey + 1.6, QUESTION)
    elif kind == "surprise":
        cv.put(ex, ey - 1.5, SWEAT); cv.put(ex, ey - 0.5, SWEAT)
        cv.put(ex, ey + 1.2, SWEAT)
    elif kind == "music":
        cv.put(ex + 1, ey - 1.6, STAR); cv.put(ex + 1, ey - 0.4, STAR)
        cv.put(ex + 1, ey + 0.6, STAR); cv.ellipse(ex, ey + 0.9, 1.1, 0.9, STAR)


def draw_stand(cv, p):
    bx, by = p["bx"], p["by"]
    draw_tail(cv, bx - 6.2, by - 1.0, p.get("tail_a", 3.0), p.get("tail_curl", -0.20),
              length=p.get("tail_len", 1.85))
    for leg in p["far"]:
        draw_leg(cv, *leg, 3.0, DARK)

    cv.ellipse(bx, by, 6.9, 4.3, MID)                # barrel
    cv.ellipse(bx - 4.0, by - 0.5, 4.6, 4.2, MID)    # haunch
    cv.ellipse(bx + 4.6, by - 0.7, 4.4, 4.0, MID)    # shoulder

    for leg in p["near"]:
        draw_leg(cv, *leg, 3.4, MID)

    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 4.8, by - 2.4, hx - 1.4, hy + 3.2, 5.0, 4.4, MID)   # neck
    draw_head(cv, hx, hy, p.get("eye", 1.0), p.get("tw", 0.0),
              p.get("mouth", 0), p.get("look", 0.0))
    draw_collar(cv, hx - 2.4, hy + 4.6)


def draw_eat(cv, p):
    """Head lowered to the bowl, shoulders dropped, haunches still high."""
    bx, by = p["bx"], p["by"]
    draw_tail(cv, bx - 6.2, by - 1.4, p.get("tail_a", 2.7), p.get("tail_curl", -0.16))
    for leg in p["far"]:
        draw_leg(cv, *leg, 3.0, DARK)

    cv.ellipse(bx, by + 0.4, 6.9, 4.1, MID)          # barrel
    cv.ellipse(bx - 4.2, by - 0.8, 4.6, 4.2, MID)    # haunch stays up
    cv.ellipse(bx + 4.6, by + 1.4, 4.2, 3.8, MID)    # shoulders dropped

    for leg in p["near"]:
        draw_leg(cv, *leg, 3.4, MID)

    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 4.6, by - 0.4, hx - 2.0, hy - 2.2, 5.0, 4.2, MID)   # neck reaches down
    draw_head(cv, hx, hy, p.get("eye", 0.35), p.get("tw", 0.0), p.get("mouth", 1))
    draw_collar(cv, hx - 4.6, hy - 1.2)


def draw_sit(cv, p):
    bx, by = p["bx"], p["by"]
    draw_tail(cv, bx - 4.2, by + 3.6, p.get("tail_a", 3.2), p.get("tail_curl", 0.36),
              seg=8, length=1.8)
    cv.ellipse(bx - 2.0, by + 3.0, 6.0, 3.9, DARK)   # rump settled on the floor
    cv.ellipse(bx - 3.0, by + 0.2, 4.4, 4.4, DARK)   # folded hind leg
    cv.ellipse(bx - 0.6, by + 1.4, 4.2, 4.6, MID)    # flank
    cv.ellipse(bx + 3.4, by + 0.2, 3.9, 5.4, MID)    # upright chest column

    for i, off in enumerate((-0.4, 2.6)):            # front legs, gap between them
        c = DARK if i == 0 else MID
        cv.taper(bx + 3.2 + off, by + 2.4, bx + 3.5 + off, GROUND - 1.2, 2.8, 2.5, c)
        cv.ellipse(bx + 4.0 + off, GROUND - 1.0, 1.8, 1.2, c)

    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 3.4, by - 3.8, hx - 1.4, hy + 3.2, 4.6, 4.4, MID)
    draw_head(cv, hx, hy, p.get("eye", 1.0), p.get("tw", 0.0),
              p.get("mouth", 0), p.get("look", 0.0), yawn=p.get("yawn", 0.0))
    draw_collar(cv, hx - 2.4, hy + 4.6)
    if p.get("scratch") is not None:
        # Drawn last and in the lit tone, routed in front of the chest — inside the
        # body mass it simply disappears against the fur.
        sy = p["scratch"]
        hip = (bx + 0.6, by + 3.2)
        knee = (bx + 3.0, by + 0.4 + sy * 0.4)
        paw = (hx - 3.4, hy + 3.2 + sy)
        cv.taper(hip[0], hip[1], knee[0], knee[1], 3.6, 3.0, LIGHT)
        cv.taper(knee[0], knee[1], paw[0], paw[1], 3.0, 2.4, LIGHT)
        cv.ellipse(paw[0], paw[1] - 0.4, 2.1, 1.7, RIM)
    for i in range(p.get("stars", 0)):          # dazed birdies
        a = p.get("star_phase", 0.0) + i * math.tau / 3
        cv.put(hx + math.cos(a) * 6.5, hy - 8.4 + math.sin(a) * 2.2, STAR)
    if p.get("emote"):
        draw_emote(cv, hx, hy, p["emote"], p.get("emote_t", 0.0))
    if p.get("paw"):
        px, py = p["paw"]
        cv.taper(bx + 4.0, by + 2.0, bx + px, by + py, 3.0, 2.4, LIGHT)
        cv.ellipse(bx + px, by + py - 0.8, 2.0, 1.5, LIGHT)


def draw_sleep(cv, p):
    """Curled into a comma: spine arched, nose tucked toward the hind paws."""
    bx, by, br = p["bx"], p["by"], p["br"]
    cv.ellipse(bx, by, br, br * 0.70, MID)                     # curled back
    cv.ellipse(bx - br * 0.34, by + br * 0.26, br * 0.62, br * 0.44, DARK)
    # head clears the body to the right, so it catches its own rim light
    hx, hy = bx + br * 0.98, by + br * 0.36
    cv.ellipse(hx, hy, 4.4, 3.9, MID)                          # head resting low
    # ears folded back against the skull
    cv.poly([(hx - 4.0, hy - 1.6), (hx - 6.8, hy - 6.6), (hx - 1.0, hy - 3.4)], DARK)
    near = [(hx - 0.4, hy - 3.4), (hx + 0.8, hy - 8.2), (hx + 3.8, hy - 1.6)]
    cv.poly(near, MID)
    cv.poly([(near[0][0] + 1.0, near[0][1] - 0.4),
             (near[1][0] + 0.2, near[1][1] + 2.6),
             (near[2][0] - 1.2, near[2][1] - 0.4)], INNER_EAR)
    cv.ellipse(hx + 2.2, hy + 1.4, 2.4, 1.8, LIGHT)            # muzzle
    cv.rect(hx - 0.4, hy - 0.2, hx + 1.4, hy - 0.2, OUTLINE)   # closed eye
    cv.put(hx + 3.8, hy + 0.9, NOSE)
    for i in (1, 3):
        cv.put(hx + 4.4 + i, hy + 1.4 + i * 0.3, WHISKER)
    # tail sweeps along the floor and flicks up in front of the nose
    draw_tail(cv, bx - br * 0.55, by + br * 0.56, -0.15, 0.22, seg=9, length=1.75)


def draw_dangle(cv, p):
    """Picked up: body hangs vertical, legs drop, tail streams down."""
    bx, by, sw = p["bx"], p["by"], p.get("sway", 0.0)
    draw_tail(cv, bx - 3.0, by + 4.0, -1.45 + sw * 0.16, 0.10, seg=8, length=1.8)
    for i, (ox, oy) in enumerate(((-3.0, 1.0), (-1.0, 1.8), (2.2, 1.4), (3.8, 0.8))):
        c = DARK if i % 2 == 0 else MID
        hip = (bx + ox, by + oy)
        foot = (bx + ox + sw * 1.5, by + oy + 7.4)
        knee = (bx + ox + sw * 0.8, by + oy + 3.8)
        draw_leg(cv, hip, knee, foot, 2.9, c)
    cv.ellipse(bx, by + 1.0, 5.4, 6.6, MID)                    # body hangs
    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 0.6, by - 4.6, hx - 1.0, hy + 3.4, 4.8, 4.4, MID)
    draw_head(cv, hx, hy, p.get("eye", 0.35), 0.0, 1, p.get("look", -0.4))
    draw_collar(cv, hx - 2.4, hy + 4.6)


BOWL_W, BOWL_H = 15, 10
CERAMIC      = (96, 102, 124, 255)
CERAMIC_DK   = (58, 62, 78, 255)
KIBBLE       = (124, 88, 56, 255)
KIBBLE_DK    = (92, 64, 40, 255)


FISH_C     = (150, 150, 168, 255)
FISH_DK    = (104, 104, 124, 255)
TREAT_C    = (196, 132, 92, 255)
MILK_C     = (222, 224, 230, 255)

def _bowl_base(cv):
    cx, base = BOWL_W / 2 - 0.5, BOWL_H - 2.5
    cv.poly([(1.5, 4.5), (BOWL_W - 2.5, 4.5),
             (BOWL_W - 4.0, base + 1.4), (3.0, base + 1.4)], CERAMIC_DK)
    cv.ellipse(cx, 4.6, BOWL_W / 2 - 1.2, 1.7, CERAMIC)      # rim
    cv.ellipse(cx, 5.1, BOWL_W / 2 - 2.4, 1.1, CERAMIC_DK)   # hollow
    return cx

def draw_bowl(kind, full):
    """A dish of food. `full` False is the same dish licked clean."""
    cv = Canvas(BOWL_W, BOWL_H)
    cx = _bowl_base(cv)
    if full:
        if kind == "kibble":
            cv.ellipse(cx, 4.3, BOWL_W / 2 - 2.6, 1.6, KIBBLE)
            for dx, dy in ((-2, 3.4), (0, 3.0), (2, 3.5), (-1, 4.4), (1, 4.3)):
                cv.put(cx + dx, dy, KIBBLE_DK if (dx + dy) % 2 else KIBBLE)
        elif kind == "fish":
            cv.ellipse(cx - 0.5, 3.6, 3.6, 1.5, FISH_C)          # body
            cv.poly([(cx + 3.0, 3.6), (cx + 5.0, 2.4), (cx + 5.0, 4.8)], FISH_DK)  # tail
            cv.put(cx - 2.4, 3.4, OUTLINE)                        # eye
            for i in range(3):
                cv.put(cx - 1.0 + i * 1.3, 3.6, FISH_DK)         # scales
        elif kind == "treat":
            for dx, dy in ((-2.4, 3.6), (0.2, 3.2), (2.4, 3.7)):
                cv.ellipse(cx + dx, dy, 1.5, 1.2, TREAT_C)       # heart-shaped biscuits
                cv.put(cx + dx, dy - 0.9, TREAT_C)
        elif kind == "milk":
            cv.ellipse(cx, 4.0, BOWL_W / 2 - 2.6, 1.5, MILK_C)   # saucer of milk
            cv.ellipse(cx - 1.2, 3.7, 1.0, 0.6, (245, 246, 250, 255))
    outline_pass(cv)
    return cv.to_image()

BOWL_KINDS = ["kibble", "fish", "treat", "milk"]


def draw_land(cv, p):
    """Impact: legs splayed, body squashed flat, head tucked."""
    bx, by = p["bx"], p["by"]
    squash = p.get("squash", 1.0)          # 1 = flattest, 0 = recovered
    draw_tail(cv, bx - 6.0, by - 0.6, 3.05 + squash * 0.25, -0.10)

    spread = 3.2 + squash * 4.0
    for i, (dx, dy) in enumerate(((-4.4, 1.4), (4.0, 1.2))):
        foot = (bx + dx - spread, GROUND - 1.4)
        draw_leg(cv, (bx + dx, by + dy), (bx + dx - spread * 0.6, by + dy + 2.4), foot, 2.8, DARK)
    for i, (dx, dy) in enumerate(((-3.0, 1.8), (5.4, 1.6))):
        foot = (bx + dx + spread, GROUND - 1.4)
        draw_leg(cv, (bx + dx, by + dy), (bx + dx + spread * 0.6, by + dy + 2.4), foot, 3.2, MID)

    cv.ellipse(bx, by + squash * 1.2, 7.6 + squash * 1.4, 4.3 - squash * 1.5, MID)
    cv.ellipse(bx - 4.2, by + squash, 4.8, 4.0 - squash * 1.2, MID)
    cv.ellipse(bx + 4.6, by + squash, 4.4, 3.8 - squash * 1.1, MID)

    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 4.8, by - 1.2 + squash, hx - 1.4, hy + 3.0, 5.0, 4.4, MID)
    draw_head(cv, hx, hy, p.get("eye", 0.15), 0.0, 1, 0.0, flat=p.get("flat", 0.55))
    draw_collar(cv, hx - 2.4, hy + 4.6)


def draw_stretch(cv, p):
    """The long one: front paws reaching forward, chest down, haunches up."""
    bx, by = p["bx"], p["by"]
    reach = p.get("reach", 1.0)
    draw_tail(cv, bx - 6.0, by - 2.0, 1.55 - reach * 0.2, -0.14, length=2.05)

    # hind legs stay planted and straight, lifting the rear
    for dx, c in ((-4.6, DARK), (-3.0, MID)):
        cv.taper(bx + dx, by + 1.0, bx + dx - 0.6, GROUND - 2.0, 3.0, 2.6, c)
        cv.ellipse(bx + dx - 0.8, GROUND - 1.4, 1.9, 1.3, c)

    cv.ellipse(bx - 3.4, by - 2.2 - reach * 2.2, 5.2, 4.4, MID)        # haunch hoisted up
    cv.ellipse(bx + 1.2, by + 1.4 + reach * 1.6, 6.4, 3.4, MID)        # spine dips
    cv.ellipse(bx + 5.6, by + 3.6 + reach * 2.2, 4.0, 3.0, MID)        # chest pressed down

    # front legs slide forward along the floor, ahead of the muzzle
    for dy, c in ((0.4, DARK), (1.6, MID)):
        toe = bx + 10.0 + reach * 2.6
        cv.taper(bx + 5.8, by + 3.4 + dy + reach * 1.6, toe, GROUND - 1.1, 2.9, 2.3, c)
        cv.ellipse(toe + 0.8, GROUND - 0.9, 2.2, 1.2, c)

    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 6.6, by + 2.6 + reach * 1.6, hx - 1.4, hy + 2.6, 4.4, 4.0, MID)
    draw_head(cv, hx, hy, p.get("eye", 0.15), 0.0, 0, 0.0, yawn=p.get("yawn", 0.0))
    draw_collar(cv, hx - 2.6, hy + 4.2)


def draw_crouch(cv, p):
    """Hunting crouch: chest low, rear high and wiggling before a pounce."""
    bx, by = p["bx"], p["by"]
    wig = p.get("wiggle", 0.0)
    draw_tail(cv, bx - 5.8, by + 0.4, 3.15, 0.05 + wig * 0.10, length=1.75)

    for dx, c in ((-4.4 + wig, DARK), (-2.8 + wig, MID)):     # coiled hind legs
        cv.taper(bx + dx, by + 0.6, bx + dx - 1.6, by + 3.6, 3.2, 2.8, c)
        cv.taper(bx + dx - 1.6, by + 3.6, bx + dx + 0.4, GROUND - 1.4, 2.8, 2.4, c)
        cv.ellipse(bx + dx + 1.0, GROUND - 1.2, 1.9, 1.2, c)

    cv.ellipse(bx - 3.2, by - 0.8, 5.0, 4.2, MID)             # rear up
    cv.ellipse(bx + 1.6, by + 2.4, 6.4, 3.4, MID)             # low body
    cv.ellipse(bx + 5.8, by + 3.4, 4.2, 3.0, MID)             # chest down

    for dy, c in ((0.4, DARK), (1.4, MID)):                   # front legs folded under
        cv.taper(bx + 6.0, by + 3.4 + dy, bx + 7.6, GROUND - 1.4, 2.8, 2.3, c)
        cv.ellipse(bx + 8.2, GROUND - 1.2, 1.9, 1.2, c)

    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 7.0, by + 2.6, hx - 1.4, hy + 2.8, 4.6, 4.2, MID)
    draw_head(cv, hx, hy, 1.0, p.get("tw", 0.0), 0, p.get("look", 0.0))
    draw_collar(cv, hx - 2.6, hy + 4.2)


def draw_loaf(cv, p):
    """Bread loaf: paws tucked, upright and alert, but going nowhere."""
    bx, by, br = p["bx"], p["by"], p["br"]
    draw_tail(cv, bx - br * 0.55, by + br * 0.5, -0.2, 0.20, seg=8, length=1.7)
    cv.ellipse(bx, by, br, br * 0.78, MID)
    cv.ellipse(bx - br * 0.36, by + br * 0.30, br * 0.6, br * 0.44, DARK)
    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + br * 0.5, by - br * 0.35, hx - 1.4, hy + 3.4, 4.8, 4.4, MID)
    draw_head(cv, hx, hy, p.get("eye", 1.0), p.get("tw", 0.0), 0, 0.0)
    draw_collar(cv, hx - 2.4, hy + 4.6)


def draw_flop(cv, p):
    """Lying on his side, fully relaxed, legs stretched out along the floor."""
    bx, by = p["bx"], p["by"]
    br = p.get("breath", 0.0)
    # legs stick out sideways, stacked
    for dx, dy, c in ((-2.0, 0.4, DARK), (-3.4, 1.6, DARK), (3.0, 0.4, MID), (4.4, 1.6, MID)):
        cv.taper(bx + dx, by + dy, bx + dx + (2.6 if dx > 0 else -2.6), GROUND - 1.2, 2.7, 2.3, c)
        cv.ellipse(bx + dx + (3.2 if dx > 0 else -3.2), GROUND - 1.0, 1.8, 1.1, c)
    cv.ellipse(bx, by + 0.5, 9.4, 3.6 + br, MID)              # long body on its side
    cv.ellipse(bx - 5.0, by + 0.4, 4.4, 3.2, DARK)           # haunch
    draw_tail(cv, bx + 8.4, by + 1.6, -0.1, -0.14, length=1.9)
    hx, hy = p["hx"], p["hy"]                                 # head resting low
    cv.ellipse(hx, hy, 4.6, 4.0, MID)
    cv.poly([(hx - 3.6, hy - 1.4), (hx - 6.2, hy - 5.6), (hx - 0.8, hy - 3.2)], DARK)
    near = [(hx - 0.2, hy - 3.2), (hx + 1.0, hy - 7.4), (hx + 3.8, hy - 1.4)]
    cv.poly(near, MID)
    cv.poly([(near[0][0]+1.0, near[0][1]-0.4), (near[1][0]+0.2, near[1][1]+2.6),
             (near[2][0]-1.2, near[2][1]-0.4)], INNER_EAR)
    cv.ellipse(hx + 2.2, hy + 1.2, 2.3, 1.7, LIGHT)
    cv.rect(hx - 0.2, hy - 0.2, hx + 1.6, hy - 0.2, OUTLINE)  # closed content eye
    cv.put(hx + 3.7, hy + 0.9, NOSE)


def draw_rollover(cv, p):
    """On his back, belly up, four paws in the air — peak trust."""
    bx = p["bx"]
    gy = GROUND - 3.0
    wig = p.get("wiggle", 0.0)
    draw_tail(cv, bx - 8.4, gy + 0.5, 0.15, 0.16, length=1.7)
    # dark curled back pressed to the floor
    cv.ellipse(bx, gy + 1.4, 9.0, 2.9, DARK)
    # big pale belly dome facing up — the giveaway that he's on his back
    cv.ellipse(bx + 0.5, gy - 1.6, 7.2, 3.2, LIGHT)
    cv.ellipse(bx + 0.5, gy - 0.4, 6.6, 2.4, RIM)
    # four paws sticking straight up, curled, waving a little
    for dx in (-4.6, -2.2, 2.2, 4.6):
        sway = math.sin(wig * math.tau + dx) * 0.8
        cv.taper(bx + dx, gy - 2.6, bx + dx + sway, gy - 7.2, 2.4, 1.9, DARK)
        cv.ellipse(bx + dx + sway, gy - 7.4, 1.7, 1.4, MID)
    # head tipped back off the right end, chin pointing up
    hx, hy = bx + 8.2, gy + 0.6
    cv.ellipse(hx, hy, 4.4, 3.9, MID)
    cv.poly([(hx + 0.6, hy - 2.6), (hx + 2.0, hy - 7.0), (hx + 3.6, hy - 1.6)], MID)   # ear up
    cv.poly([(hx + 1.2, hy - 2.8), (hx + 2.0, hy - 5.6), (hx + 3.0, hy - 1.8)], INNER_EAR)
    cv.ellipse(hx + 1.6, hy + 1.8, 2.2, 1.7, LIGHT)          # upside-down muzzle points up
    cv.put(hx + 2.8, hy + 2.6, NOSE)
    cv.rect(hx - 0.6, hy - 0.4, hx + 1.2, hy - 0.4, OUTLINE)  # blissful squint


def draw_dog_playbow(cv, p):
    """The dog play-bow: chest and front paws down, rear end and tail up high."""
    bx = p["bx"]
    gy = GROUND
    # rear legs standing tall (rump up)
    for dx, c in ((-6.0, DARK), (-4.0, MID)):
        cv.taper(bx + dx, gy - 12, bx + dx, gy - 1.2, 3.0, 2.6, c)
        cv.ellipse(bx + dx, gy - 1.0, 1.9, 1.2, c)
    cv.ellipse(bx - 4.4, gy - 12, 5.0, 4.4, MID)          # raised haunches
    cv.ellipse(bx + 1.0, gy - 8, 5.6, 4.0, MID)           # sloping back
    cv.ellipse(bx + 5.6, gy - 3.5, 4.4, 3.4, MID)         # chest dropped low
    # front legs stretched forward flat on the floor
    for dy, c in ((-0.4, MID), (0.8, DARK)):
        cv.taper(bx + 6.0, gy - 3.5 + dy, bx + 11.5, gy - 1.2, 3.0, 2.4, c)
        cv.ellipse(bx + 12.0, gy - 1.0, 2.0, 1.2, c)
    # tail up high, wagging
    draw_tail(cv, bx - 6.4, gy - 13, 1.5, 0.10, length=2.0)
    hx, hy = bx + 8.0, gy - 4.0
    draw_head(cv, hx, hy, 1.0, 0.0, 1, 0.0)              # head low, tongue out (mouth=1)
    draw_collar(cv, hx - 3.0, hy + 3.6)


def draw_arch(cv, p):
    """Spooked cat: the Halloween inverted-U. Dogs do a play-bow instead."""
    if SPECIES == "dog":
        draw_dog_playbow(cv, p)
        return
    bx = p["bx"]
    a = p.get("arch", 1.0)
    puff = p.get("puff", 1.0)
    peak = GROUND - 14 - a * 5          # how high the middle of the back rides

    # four straight, stiff, vertical legs planted wide
    for dx, c in ((-6.0, DARK), (-4.2, DARK), (4.6, MID), (6.4, MID)):
        top = peak + 4 + abs(dx) * 0.5
        cv.taper(bx + dx, top, bx + dx, GROUND - 1.2, 2.5, 2.2, c)
        cv.ellipse(bx + dx, GROUND - 1.0, 1.7, 1.1, c)

    # the arched spine, drawn as ellipses stepped along an inverted-U
    span = 7.0
    for i in range(9):
        t = i / 8                        # 0 = tail end, 1 = shoulders
        x = bx - span + t * span * 2
        y = peak + (1 - math.sin(t * math.pi)) * 6.0
        cv.ellipse(x, y, 3.4, 3.6, MID if i % 2 else DARK)

    # fat bristled tail, straight up off the rump
    for i in range(8):
        w = 1.8 + puff * 2.4 * (1 - i / 9)
        cv.ellipse(bx - span - 0.5, peak + 4 - i * 1.8, w, 1.5, DARK if i % 2 else MID)

    # head lowered at the shoulder end, ears pinned back, hiss
    hx, hy = bx + span + 1.0, peak + 5.0
    draw_head(cv, hx, hy, -2, 0.0, 1, 0.0, flat=0.75)
    draw_collar(cv, hx - 2.6, hy + 4.2)


def draw_beg(cv, p):
    """Sitting up on his haunches, front paws dangling, looking up."""
    bx, by = p["bx"], p["by"]
    paw = p.get("paw_bob", 0.0)
    draw_tail(cv, bx - 4.0, by + 5.0, 3.3, 0.30, seg=8, length=1.6)
    cv.ellipse(bx - 1.0, by + 4.2, 6.2, 4.0, DARK)           # rump on the floor
    # hind legs folded
    cv.ellipse(bx - 2.4, by + 2.6, 4.4, 3.6, DARK)
    for off in (-0.6, 2.0):
        cv.taper(bx + 2.6 + off, by + 4.0, bx + 3.0 + off, GROUND - 1.2, 2.8, 2.4, DARK)
    # upright torso
    cv.ellipse(bx + 2.6, by - 1.6, 4.6, 6.2, MID)
    # front paws held up, begging
    for dx in (0.4, 2.6):
        cv.taper(bx + 3.4 + dx, by - 3.0, bx + 4.4 + dx, by - 6.4 - paw, 2.4, 2.0, MID)
        cv.ellipse(bx + 4.6 + dx, by - 6.8 - paw, 1.6, 1.4, LIGHT)
    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 3.6, by - 5.6, hx - 1.4, hy + 3.0, 4.4, 4.0, MID)
    draw_head(cv, hx, hy, p.get("eye", 1.0), p.get("tw", 0.0), 0, 0.0)
    draw_collar(cv, hx - 2.4, hy + 4.4)
    if p.get("emote"):
        draw_emote(cv, hx, hy, p["emote"], p.get("emote_t", 0.0))


def draw_pounce(cv, p):
    """Mid-leap: body stretched diagonally, front paws reaching, hind legs kicked back."""
    bx, by = p["bx"], p["by"]
    ext = p.get("extend", 1.0)
    draw_tail(cv, bx - 6.4, by + 2.0, 2.6, -0.18, length=2.0)
    # hind legs kicked out behind and down
    for dx, dy, c in ((-5.0, 2.6, DARK), (-3.6, 3.4, MID)):
        cv.taper(bx + dx, by + 1.0, bx + dx - 2.0 * ext, by + dy + 2.4 * ext, 2.8, 2.2, c)
        cv.ellipse(bx + dx - 2.4 * ext, by + dy + 2.6 * ext, 1.7, 1.2, c)
    cv.ellipse(bx, by, 7.2, 3.8, MID)                        # streamlined body
    cv.ellipse(bx - 4.0, by + 0.4, 4.2, 3.4, MID)
    # front paws reaching forward
    for dy, c in ((-0.6, MID), (0.8, DARK)):
        toe = bx + 9.0 + ext * 3.0
        cv.taper(bx + 5.4, by + dy, toe, by - 1.4 - dy, 2.8, 2.2, c)
        cv.ellipse(toe + 0.4, by - 1.6 - dy, 1.8, 1.3, c)
    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 5.0, by - 1.6, hx - 1.4, hy + 3.0, 4.4, 4.0, MID)
    draw_head(cv, hx, hy, 1.0, 0.0, 1, 0.2, flat=0.3)
    draw_collar(cv, hx - 2.4, hy + 4.2)


def draw_headlow(cv, p):
    """Base for sniffing / playing: standing with the nose dipped to the floor."""
    bx, by = p["bx"], p["by"]
    draw_tail(cv, bx - 6.2, by - 1.2, p.get("tail_a", 2.9), p.get("tail_curl", -0.18),
              length=p.get("tail_len", 1.9))
    for leg in p["far"]:
        draw_leg(cv, *leg, 3.0, DARK)
    cv.ellipse(bx, by, 6.9, 4.3, MID)
    cv.ellipse(bx - 4.0, by - 0.6, 4.6, 4.2, MID)
    cv.ellipse(bx + 4.6, by + 0.6, 4.4, 3.8, MID)
    for leg in p["near"]:
        draw_leg(cv, *leg, 3.4, MID)
    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 4.8, by - 1.0, hx - 1.4, hy - 1.0, 5.0, 4.4, MID)
    draw_head(cv, hx, hy, p.get("eye", 1.0), p.get("tw", 0.0),
              p.get("mouth", 0), p.get("look", 0.0))
    draw_collar(cv, hx - 3.0, hy + 3.6)
    if p.get("paw_swat") is not None:
        sx = p["paw_swat"]
        cv.taper(bx + 6.0, by + 1.0, hx - 1.0 + sx, hy + 2.0, 3.0, 2.4, LIGHT)
        cv.ellipse(hx - 1.0 + sx, hy + 1.4, 2.0, 1.6, RIM)


MOUSE_W, MOUSE_H = 16, 12
MOUSE_C   = (150, 150, 166, 255)
MOUSE_DK  = (104, 104, 122, 255)
MOUSE_EAR = (150, 120, 132, 255)

def draw_mouse(run):
    """A little wind-up mouse toy. Two frames of scampering legs."""
    cv = Canvas(MOUSE_W, MOUSE_H)
    cx, cy = 8.5, 6.5
    # long tail curling behind
    cv.taper(cx + 3.4, cy + 0.6, cx + 6.6, cy - 1.6 + (1.2 if run else -1.2), 1.4, 0.6, MOUSE_DK)
    cv.ellipse(cx, cy, 4.2, 2.9, MOUSE_C)                 # body
    cv.ellipse(cx - 3.0, cy - 0.6, 2.4, 2.2, MOUSE_C)     # head toward -x (faces left)
    cv.ellipse(cx - 2.2, cy - 2.2, 1.5, 1.5, MOUSE_EAR)   # ear
    cv.put(cx - 4.4, cy - 0.4, OUTLINE)                   # nose
    cv.put(cx - 3.6, cy - 1.0, (18, 18, 22, 255))         # eye
    # little running legs
    off = 1.0 if run else -1.0
    for lx in (-1.0, 2.2):
        cv.put(cx + lx, cy + 2.6, MOUSE_DK)
        cv.put(cx + lx + off * 0.0, cy + 3.2, MOUSE_DK)
    outline_pass(cv)
    return cv.to_image()


def draw_stargaze(cv, p):
    """Sits gazing up while a shooting star streaks overhead. A rare night moment."""
    # the sitting body, ears up, eyes wide and looking up
    draw_sit(cv, {"bx": p["bx"], "by": p["by"], "hx": p["hx"], "hy": p["hy"],
                  "tail_a": 3.20, "tail_curl": 0.36, "eye": p.get("eye", 1.0),
                  "look": 0.2})
    # a small crescent moon, fixed top-left
    cv.ellipse(6.6, 4.4, 2.4, 2.4, STAR)          # moon disc
    cv.ellipse(8.2, 3.8, 2.2, 2.2, OUTLINE)       # bite out of it -> crescent
    # fixed faint stars
    for (tx, ty) in [(15, 3), (33, 6), (22, 2)]:
        cv.put_late(tx, ty, RIM)
    # the shooting star + its trail, sweeping left to right across the top
    sx = p.get("starx")
    if sx is not None:
        cv.put_late(sx, 3, STAR)
        for i in range(1, 5):
            cv.put_late(sx - i * 1.5, 3 + i * 0.6, RIM)
    # a wish sparkle above his head near the end
    for (tx, ty) in p.get("sparkles", []):
        cv.put_late(tx, ty, STAR)


BALL_W, BALL_H = 14, 14
def draw_ball():
    """A little play ball with a highlight — 2 frames for a gentle wobble."""
    frames = []
    for f in range(2):
        cv = Canvas(BALL_W, BALL_H)
        cx, cy = BALL_W / 2 - 0.5, BALL_H / 2 + (0.0 if f == 0 else -0.6)
        BALL   = (206, 116, 96, 255)
        BALL_D = (156, 78, 62, 255)
        cv.ellipse(cx, cy, 5.2, 5.2, BALL)
        cv.ellipse(cx + 1.4, cy + 1.4, 3.2, 3.2, BALL_D)   # shaded underside
        cv.ellipse(cx - 1.6, cy - 1.8, 1.6, 1.6, (240, 190, 170, 255))  # highlight
        outline_pass(cv)
        frames.append(cv.to_image())
    return frames

FEATHER_W, FEATHER_H = 16, 16
def draw_feather():
    """A feather toy — 2 frames for a little flutter."""
    frames = []
    for f in range(2):
        cv = Canvas(FEATHER_W, FEATHER_H)
        tilt = 0.0 if f == 0 else 1.0
        FTHR   = (150, 176, 214, 255)
        FTHR_D = (104, 128, 168, 255)
        QUILL  = (196, 176, 120, 255)
        # quill from bottom up
        cv.taper(6, FEATHER_H - 1, 8 + tilt, 4, 1.4, 0.8, QUILL)
        # plume
        for i in range(6):
            yy = 4 + i * 1.4
            w = 3.0 - i * 0.35
            cv.ellipse(8 + tilt - i * 0.2, yy, w, 1.2, FTHR if i % 2 else FTHR_D)
        outline_pass(cv)
        frames.append(cv.to_image())
    return frames


# ------------------------------------------------------------- animations ---

def frame(fn, p):
    cv = Canvas()
    fn(cv, p)
    warm_pass(cv)
    rim_pass(cv)
    if SPECIES == "dog":
        fluff_pass(cv)
    outline_pass(cv)
    for (x, y, c) in cv.late:
        cv.put(x, y, c)
    return cv.to_image()


BY, HX, HY = 19.6, 29.0, 12.4      # resting body y, head x, head y


def anim_idle(n=8):
    out = []
    for i in range(n):
        t = i / n
        br = math.sin(t * math.tau)
        far, near = make_legs(18.0, BY, 0.0, 0.0)
        out.append(frame(draw_stand, {
            "bx": 18.0, "by": BY - br * 0.25, "hx": HX, "hy": HY - br * 0.4,
            "far": far, "near": near,
            "tail_a": 3.02 + br * 0.16, "tail_curl": -0.20 + math.sin(t * math.tau + 1) * 0.05,
            "eye": 0.1 if i == 5 else 1.0, "tw": 0.9 if i == 2 else 0.0,
        }))
    return out


def anim_walk(n=8):
    out = []
    for i in range(n):
        ph = (i / n) * math.tau
        bob = math.sin(ph * 2) * 0.45
        far, near = make_legs(18.0, BY + bob * 0.5, ph, 3.6)
        out.append(frame(draw_stand, {
            "bx": 18.0, "by": BY + bob * 0.5, "hx": HX, "hy": HY + bob * 0.6,
            "far": far, "near": near,
            "tail_a": 2.95 + math.sin(ph) * 0.22, "tail_curl": -0.19 + math.sin(ph + 1.2) * 0.06,
        }))
    return out


def anim_sit(n=6):
    out = []
    for i in range(n):
        t = i / n
        br = math.sin(t * math.tau)
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6, "hx": 25.5, "hy": 10.6 + br * 0.35,
            "tail_a": 3.20 + br * 0.16, "tail_curl": 0.36,
            "eye": 0.1 if i == 4 else 1.0, "tw": 0.8 if i == 1 else 0.0,
        }))
    return out


def anim_groom(n=8):
    out = []
    for i in range(n):
        lick = math.sin((i / n) * math.tau)
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6,
            "hx": 25.5 - lick * 0.7, "hy": 11.4 + abs(lick) * 1.4,
            "tail_a": 3.20, "tail_curl": 0.36,
            "eye": 0.15, "mouth": 1 if lick > 0.25 else 0,
            "paw": (4.6 + lick * 0.5, -4.0 - abs(lick) * 1.1),
        }))
    return out


def anim_sleep(n=6):
    return [frame(draw_sleep, {
        "bx": 19.0, "by": 21.4, "br": 8.2 + math.sin((i / n) * math.tau) * 0.3,
    }) for i in range(n)]


def anim_drag(n=4):
    out = []
    for i in range(n):
        sw = math.sin((i / n) * math.tau)
        out.append(frame(draw_dangle, {
            "bx": 18.0 + sw * 0.5, "by": 13.0, "hx": 22.4 + sw * 0.6, "hy": 6.6,
            "sway": sw, "eye": 0.35,
        }))
    return out


def anim_fall(n=2):
    out = []
    for i in range(n):
        far, near = make_legs(18.0, 18.4, 0.0, 0.0, ground=GROUND - 2.4 - i)
        far = [(h, k, (f[0] + 3.0 + i, f[1])) for h, k, f in far]
        near = [(h, k, (f[0] - 3.0 - i, f[1])) for h, k, f in near]
        out.append(frame(draw_stand, {
            "bx": 18.0, "by": 18.4, "hx": HX, "hy": 11.4,
            "far": far, "near": near,
            "tail_a": 2.05, "tail_curl": -0.30, "mouth": 1,
        }))
    return out


def anim_happy(n=6):
    """Tail straight up, eyes squeezed shut -- the petting reaction."""
    out = []
    for i in range(n):
        t = i / n
        hop = abs(math.sin(t * math.pi * 2)) * 1.5
        far, near = make_legs(18.0, BY - hop * 0.5, 0.0, 0.0)
        out.append(frame(draw_stand, {
            "bx": 18.0, "by": BY - hop * 0.5, "hx": HX, "hy": HY - hop,
            "far": far, "near": near,
            "tail_a": 1.42, "tail_curl": -0.04 + math.sin(t * math.tau) * 0.07,
            "tail_len": 2.0, "eye": 0.1, "mouth": 1,
            "tw": math.sin(t * math.tau) * 0.7,
        }))
    return out


def anim_eat(n=8):
    """Chewing: the head dips into the bowl and lifts a little on each bite."""
    out = []
    for i in range(n):
        t = i / n
        bite = math.sin(t * math.tau * 2)
        far, near = make_legs(16.0, BY + 0.6, 0.0, 0.0)
        out.append(frame(draw_eat, {
            "bx": 16.0, "by": BY + 0.6,
            "hx": 30.0, "hy": 22.0 + bite * 0.7,
            "far": far, "near": near,
            "tail_a": 2.90 + math.sin(t * math.tau) * 0.14,
            "tail_curl": -0.26,
            "eye": 0.35, "mouth": 1 if bite > 0 else 0,
            "tw": math.sin(t * math.tau) * 0.5,
        }))
    return out


def anim_land(n=4):
    """Hits the ground, squashes, springs back."""
    out = []
    for i in range(n):
        squash = [1.0, 0.62, 0.24, 0.0][i]
        out.append(frame(draw_land, {
            "bx": 18.0, "by": BY + 1.4 + squash * 1.6,
            "hx": HX - squash * 1.6, "hy": HY + 3.4 + squash * 2.6,
            "eye": 0.15 if squash > 0.4 else 1.0,
            "squash": squash, "flat": 0.55 * squash,
        }))
    return out


def anim_dizzy(n=8):
    """Sat down seeing birdies after a long drop."""
    out = []
    for i in range(n):
        t = i / n
        wob = math.sin(t * math.tau * 2)
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6,
            "hx": 25.5 + wob * 0.8, "hy": 10.8 + abs(wob) * 0.5,
            "tail_a": 3.20, "tail_curl": 0.36,
            "eye": -1.0, "tw": wob * 0.7,
            "stars": 3, "star_phase": t * math.tau,
        }))
    return out


def anim_stretch(n=8):
    """Long luxurious stretch, held at the peak."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        # ease out and back, lingering at full extension
        reach = math.sin(min(1.0, t * 1.35) * math.pi) ** 0.6
        out.append(frame(draw_stretch, {
            "bx": 14.5, "by": BY - 1.6,
            "hx": 25.0 + reach * 0.8, "hy": 17.8 + reach * 3.0,
            "reach": reach,
            "eye": 0.12 if reach > 0.4 else 1.0,
            "yawn": max(0.0, reach - 0.45) * 1.5,
        }))
    return out


def anim_yawn(n=8):
    """Sits, opens wide, blinks it off."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        open_ = math.sin(min(1.0, t * 1.2) * math.pi) ** 0.7
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6,
            "hx": 25.5, "hy": 10.6 - open_ * 1.0,
            "tail_a": 3.20, "tail_curl": 0.36,
            "eye": 0.12 if open_ > 0.35 else 1.0,
            "yawn": open_,
        }))
    return out


def anim_scratch(n=8):
    """Hind foot going at an ear, fast."""
    out = []
    for i in range(n):
        buzz = math.sin((i / n) * math.tau * 3)
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6,
            "hx": 25.5, "hy": 11.0 + buzz * 0.4,
            "tail_a": 3.20, "tail_curl": 0.36,
            "eye": 0.15, "tw": buzz * 0.8,
            "scratch": buzz * 1.1,
        }))
    return out


def anim_loaf(n=6):
    out = []
    for i in range(n):
        t = i / n
        br = math.sin(t * math.tau)
        out.append(frame(draw_loaf, {
            "bx": 18.5, "by": 22.2, "br": 8.0 + br * 0.28,
            "hx": 27.0, "hy": 13.0 + br * 0.35,
            "eye": 0.1 if i == 4 else 1.0,
            "tw": 0.7 if i == 1 else 0.0,
        }))
    return out


def anim_run(n=8):
    """Zoomies: longer stride, body low, tail streaming out behind."""
    out = []
    for i in range(n):
        ph = (i / n) * math.tau
        bob = math.sin(ph * 2) * 0.9
        far, near = make_legs(18.0, BY + 1.0 + bob * 0.4, ph, 7.0)
        out.append(frame(draw_stand, {
            "bx": 18.0, "by": BY + 1.0 + bob * 0.4,
            "hx": HX + 0.8, "hy": HY + 1.6 + bob * 0.6,
            "far": far, "near": near,
            "tail_a": 3.05 + math.sin(ph) * 0.12, "tail_curl": -0.06,
            "tail_len": 2.05, "eye": 1.0, "mouth": 1,
        }))
    return out


def anim_wiggle(n=8):
    """Butt wiggle before the pounce."""
    out = []
    for i in range(n):
        wig = math.sin((i / n) * math.tau * 2) * 1.1
        out.append(frame(draw_crouch, {
            "bx": 16.0, "by": BY - 0.4,
            "hx": 28.0, "hy": 18.6,
            "wiggle": wig, "tw": wig * 0.5, "look": wig * 0.3,
        }))
    return out


def _emote_over(pose_fn, base, kind, n=6, hold=True):
    """Wraps a resting pose with a floating emote that bobs and fades in."""
    out = []
    for i in range(n):
        t = i / n
        params = dict(base)
        params["emote"] = kind
        params["emote_t"] = math.sin(t * math.tau) * 0.6 + (0 if hold else t)
        out.append(frame(pose_fn, params))
    return out


def anim_love(n=6):
    return _emote_over(draw_sit, {
        "bx": 17.5, "by": 18.6, "hx": 25.5, "hy": 10.6,
        "tail_a": 3.20, "tail_curl": 0.36, "eye": 0.12, "mouth": 1,
    }, "love", n)


def anim_angry(n=6):
    out = []
    for i in range(n):
        t = i / n
        shake = math.sin(t * math.tau * 3) * 0.5
        far, near = make_legs(18.0, BY, 0.0, 0.0)
        p = {
            "bx": 18.0 + shake, "by": BY, "hx": HX, "hy": HY,
            "far": far, "near": near,
            "tail_a": 2.6 + shake * 0.2, "tail_curl": 0.30,
            "tail_len": 2.1, "eye": -2, "tw": 0.8, "emote": "anger",
            "emote_t": t,
        }
        out.append(frame(draw_stand, p))
    return out


def anim_curious(n=6):
    out = []
    for i in range(n):
        t = i / n
        tilt = math.sin(t * math.tau) * 0.4
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6, "hx": 25.5, "hy": 10.6 + tilt,
            "tail_a": 3.20, "tail_curl": 0.36, "eye": 1.0,
            "look": tilt, "tw": tilt, "emote": "question", "emote_t": t,
        }))
    return out


def anim_surprise(n=6):
    out = []
    for i in range(n):
        t = i / n
        pop = 1.0 if i < 2 else max(0.0, 1.0 - (i - 2) / 4)
        far, near = make_legs(18.0, BY - pop * 1.4, 0.0, 0.0)
        out.append(frame(draw_stand, {
            "bx": 18.0, "by": BY - pop * 1.4, "hx": HX, "hy": HY - pop * 1.6,
            "far": far, "near": near,
            "tail_a": 1.7, "tail_curl": 0.05, "tail_len": 2.2,   # tail bottled up
            "eye": 1.0, "tw": pop, "emote": "surprise", "emote_t": t,
        }))
    return out


def anim_purr(n=6):
    """Content, eyes shut, little music note — the pet reward."""
    return _emote_over(draw_loaf, {
        "bx": 18.5, "by": 22.2, "br": 8.0, "hx": 27.0, "hy": 13.0, "eye": 0.12,
    }, "music", n)


def anim_flop(n=6):
    return [frame(draw_flop, {
        "bx": 18.0, "by": 24.4, "hx": 8.5, "hy": 24.0,
        "breath": math.sin((i / n) * math.tau) * 0.5,
    }) for i in range(n)]


def anim_rollover(n=6):
    return [frame(draw_rollover, {"bx": 18.0, "wiggle": i / n}) for i in range(n)]


def anim_arch(n=6):
    out = []
    for i in range(n):
        t = i / n
        a = min(1.0, t * 2.2)
        puff = math.sin(min(1.0, t * 1.6) * math.pi * 0.5)
        out.append(frame(draw_arch, {"bx": 19.0, "arch": a, "puff": puff}))
    return out


def anim_beg(n=6):
    out = []
    for i in range(n):
        t = i / n
        out.append(frame(draw_beg, {
            "bx": 17.0, "by": 17.0, "hx": 24.5, "hy": 7.6,
            "paw_bob": math.sin(t * math.tau * 2) * 0.8,
            "eye": 1.0, "tw": 0.3 if i % 2 else 0.0,
        }))
    return out


def anim_pounce(n=4):
    out = []
    for i in range(n):
        t = i / (n - 1)
        # rises then drives forward
        arc = math.sin(t * math.pi)
        out.append(frame(draw_pounce, {
            "bx": 16.0 + t * 4.0, "by": BY - arc * 4.0,
            "hx": 27.0 + t * 4.0, "hy": HY - arc * 3.0,
            "extend": 0.4 + t * 0.8,
        }))
    return out


def anim_beg_wait(n=6):   # alias kept for clarity if referenced
    return anim_beg(n)


def anim_sniff(n=8):
    out = []
    for i in range(n):
        ph = (i / n) * math.tau
        step = math.sin(ph) * 2.0
        far, near = make_legs(18.0, BY, ph, 1.4)
        out.append(frame(draw_headlow, {
            "bx": 18.0, "by": BY, "hx": 31.5 + step * 0.2, "hy": 21.0,
            "far": far, "near": near, "eye": 0.5, "mouth": 1 if i % 3 == 0 else 0,
            "tail_a": 2.9, "tail_curl": -0.14,
        }))
    return out


def anim_play(n=8):
    """Bats at something on the ground in front of him."""
    out = []
    for i in range(n):
        swat = math.sin((i / n) * math.tau * 2)
        far, near = make_legs(18.0, BY, 0.0, 0.0)
        out.append(frame(draw_headlow, {
            "bx": 18.0, "by": BY, "hx": 30.0, "hy": 18.0,
            "far": far, "near": near, "eye": 1.0, "mouth": 1,
            "tail_a": 2.5, "tail_curl": 0.24, "tail_len": 2.05,
            "paw_swat": 2.0 + swat * 3.0,
        }))
    return out


def anim_knead(n=6):
    """Making biscuits: front paws push down alternately."""
    out = []
    for i in range(n):
        push = math.sin((i / n) * math.tau * 2)
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6, "hx": 25.5, "hy": 11.0,
            "tail_a": 3.20, "tail_curl": 0.36, "eye": 0.2,
            "paw": (4.6 + push * 0.4, -2.2 - push * 1.6),
        }))
    return out


def anim_blep(n=6):
    """Sits, tongue caught sticking out."""
    out = []
    for i in range(n):
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6, "hx": 25.5, "hy": 10.6,
            "tail_a": 3.20, "tail_curl": 0.36,
            "eye": 1.0, "mouth": 1 if i >= 1 else 0,
        }))
    return out


def anim_chatter(n=8):
    """Bird-watching: fixed stare, jaw chattering, tail flicking."""
    out = []
    for i in range(n):
        chat = i % 2
        flick = math.sin((i / n) * math.tau * 2) * 0.4
        out.append(frame(draw_sit, {
            "bx": 17.5, "by": 18.6, "hx": 25.5, "hy": 10.6,
            "tail_a": 3.20 + flick, "tail_curl": 0.36,
            "eye": 1.0, "yawn": 0.18 if chat else 0.0, "look": 0.3,
            "emote": "music" if i % 4 == 0 else None,
        }))
    return out


def anim_rub(n=6):
    """Cheek-rub / headbonk, leaning in and back."""
    out = []
    for i in range(n):
        lean = math.sin((i / n) * math.tau)
        far, near = make_legs(18.0, BY, 0.0, 0.0)
        out.append(frame(draw_stand, {
            "bx": 18.0 + lean * 1.2, "by": BY,
            "hx": HX + lean * 1.6, "hy": HY + 1.0 + abs(lean) * 0.6,
            "far": far, "near": near,
            "tail_a": 3.0, "tail_curl": -0.20, "tail_len": 2.05,
            "eye": 0.12, "look": lean * 0.4,
        }))
    return out


def draw_bellyplay(cv, p):
    """Sprawled flat on his back, belly up, batting all four paws at the air."""
    bx = p["bx"]
    gy = GROUND - 3.0
    t = p.get("t", 0.0)
    # tail flicking along the floor
    draw_tail(cv, bx - 9.0, gy + 1.0, 0.1 + math.sin(t * math.tau) * 0.2, 0.12, length=1.7)
    # dark back flat on the ground, wide and low
    cv.ellipse(bx, gy + 1.6, 10.0, 2.6, DARK)
    # big pale belly, the whole length of him
    cv.ellipse(bx + 0.5, gy - 0.8, 8.4, 2.9, LIGHT)
    cv.ellipse(bx + 0.5, gy + 0.2, 7.8, 2.2, RIM)
    # four paws up, batting in a lively alternating rhythm
    for i, dx in enumerate((-5.2, -2.6, 2.4, 5.0)):
        bat = math.sin(t * math.tau * 2 + i * 1.7)
        px = bx + dx + bat * 1.6
        py = gy - 3.2 - abs(bat) * 2.6
        cv.taper(bx + dx, gy - 1.6, px, py, 2.5, 1.9, DARK)
        cv.ellipse(px, py - 0.4, 1.7, 1.4, MID)
    # head tipped back off the right end, relaxed, tongue out a touch
    hx, hy = bx + 8.6, gy + 0.4
    cv.ellipse(hx, hy, 4.3, 3.8, MID)
    cv.poly([(hx + 0.6, hy - 2.4), (hx + 1.9, hy - 6.6), (hx + 3.4, hy - 1.4)], MID)
    cv.poly([(hx + 1.2, hy - 2.6), (hx + 1.9, hy - 5.2), (hx + 2.8, hy - 1.6)], INNER_EAR)
    cv.ellipse(hx + 1.5, hy + 1.8, 2.1, 1.6, LIGHT)      # upside-down muzzle
    cv.put(hx + 2.7, hy + 2.5, NOSE)
    if p.get("blink"):
        cv.rect(hx - 0.6, hy - 0.4, hx + 1.2, hy - 0.4, OUTLINE)
    else:
        cv.put(hx + 0.2, hy - 0.4, EYE); cv.put(hx + 1.0, hy - 0.4, EYE)
    if p.get("tongue"):
        cv.put(hx + 2.6, hy + 3.4, PINK)


def draw_jump(cv, p):
    """A springy upward leap: body stretched tall, front paws reaching up, hind
    legs kicking down, tail streaming. Used for jumping to ledges and toys."""
    bx, by = p["bx"], p["by"]
    ext = p.get("ext", 1.0)
    draw_tail(cv, bx - 5.2, by + 3.0, -1.2, 0.14, length=2.0)   # tail trailing down
    # hind legs kicked down and back
    for dx, dy, c in ((-3.6, 3.0, DARK), (-2.0, 3.8, MID)):
        cv.taper(bx + dx, by + 1.0, bx + dx - 1.4, by + dy + 3.0 * ext, 2.7, 2.1, c)
        cv.ellipse(bx + dx - 1.6, by + dy + 3.2 * ext, 1.7, 1.2, c)
    # body reaching upward (tall, slim)
    cv.ellipse(bx, by - ext * 1.2, 4.6, 6.4, MID)
    cv.ellipse(bx + 1.0, by - 4.0 * ext, 4.2, 4.0, MID)          # chest up
    # front paws stretched up over the head
    for dx, c in ((-1.2, MID), (1.6, DARK)):
        cv.taper(bx + dx, by - 5.0 * ext, bx + dx + 0.6, by - 9.4 * ext, 2.4, 1.9, c)
        cv.ellipse(bx + dx + 0.6, by - 9.8 * ext, 1.7, 1.4, LIGHT)
    hx, hy = p["hx"], p["hy"]
    cv.taper(bx + 1.6, by - 5.6 * ext, hx - 1.2, hy + 3.0, 4.4, 4.0, MID)
    draw_head(cv, hx, hy, 1.0, 0.0, 1, 0.0, flat=0.2)
    draw_collar(cv, hx - 2.4, hy + 4.2)


def anim_jump(n=4):
    out = []
    for i in range(n):
        t = i / (n - 1)
        ext = 0.5 + 0.5 * math.sin(min(1, t * 1.2) * math.pi)   # stretch at apex
        out.append(frame(draw_jump, {
            "bx": 18.0, "by": BY - 3.0, "hx": HX, "hy": HY - 5.0 - ext * 2.0,
            "ext": ext,
        }))
    return out


def anim_stargaze(n=10):
    """A shooting star crosses the top, then a wish sparkle twinkles."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        starx = 3 + t * 34 if t < 0.72 else None
        sparkles = [(28, 5), (30, 3)] if (t >= 0.72 and i % 2 == 0) else \
                   ([(29, 4)] if t >= 0.72 else [])
        out.append(frame(draw_stargaze, {
            "bx": 17.5, "by": 18.6, "hx": 25.5, "hy": 10.2,
            "eye": 1.0, "starx": starx, "sparkles": sparkles,
        }))
    return out


def anim_bellyplay(n=8):
    out = []
    for i in range(n):
        t = i / n
        out.append(frame(draw_bellyplay, {
            "bx": 18.0, "t": t,
            "blink": i == 4, "tongue": i % 2 == 0,
        }))
    return out


ANIMS = {
    "idle":  (anim_idle,  140),
    "walk":  (anim_walk,   90),
    "sit":   (anim_sit,   190),
    "groom": (anim_groom, 120),
    "sleep": (anim_sleep, 340),
    "drag":  (anim_drag,  110),
    "fall":  (anim_fall,   90),
    "happy": (anim_happy, 110),
    "eat":     (anim_eat,     130),
    "land":    (anim_land,     70),
    "dizzy":   (anim_dizzy,   130),
    "stretch": (anim_stretch, 130),
    "yawn":    (anim_yawn,    150),
    "scratch": (anim_scratch,  80),
    "loaf":    (anim_loaf,    260),
    "run":     (anim_run,      55),
    "wiggle":   (anim_wiggle,   90),
    "love":     (anim_love,    150),
    "angry":    (anim_angry,    90),
    "curious":  (anim_curious, 150),
    "surprise": (anim_surprise, 90),
    "purr":     (anim_purr,    200),
    "flop":     (anim_flop,    280),
    "rollover": (anim_rollover, 150),
    "arch":     (anim_arch,    100),
    "beg":      (anim_beg,     150),
    "pounce":   (anim_pounce,   70),
    "sniff":    (anim_sniff,   120),
    "play":     (anim_play,     90),
    "knead":    (anim_knead,   150),
    "blep":     (anim_blep,    260),
    "chatter":  (anim_chatter,  90),
    "rub":      (anim_rub,     130),
    "stargaze": (anim_stargaze, 150),
    "bellyplay": (anim_bellyplay, 110),
    "jump":     (anim_jump,     80),
}


COLLAR_STYLES = ["none", "band", "bell", "bowtie", "bandana"]
DEFAULT_STYLE = "bell"
SPECIES_LIST = ["cat", "dog"]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    outdir = os.path.join(root, "Sources", "PetApp", "Resources", "Sprites")
    os.makedirs(outdir, exist_ok=True)

    manifest = {"frameWidth": W, "frameHeight": H, "ground": int(GROUND),
                "animations": {}, "collarStyles": COLLAR_STYLES,
                "species": SPECIES_LIST}
    global ACC_STYLE, SPECIES
    sheets = {}
    global DARK, MID, LIGHT, RIM, WARM, OUTLINE, EYE, EYE_DK, PUPIL, INNER_EAR, NOSE, WHISKER, PINK, MOUTH
    _CAT_PAL.update({k: globals()[k] for k in DOG_PAL})
    for species in SPECIES_LIST:
        SPECIES = species
        _use_palette(DOG_PAL if species == "dog" else _CAT_PAL)
        for style in COLLAR_STYLES:
            ACC_STYLE = style
            for name, (fn, ms) in ANIMS.items():
                frames = fn()
                sheet = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
                for i, f in enumerate(frames):
                    sheet.paste(f, (i * W, 0))
                sheet.save(os.path.join(outdir, f"{species}__{style}__{name}.png"))
                if species == "cat" and style == DEFAULT_STYLE:
                    sheets[name] = frames
                    manifest["animations"][name] = {"frames": len(frames), "msPerFrame": ms}
    SPECIES = "cat"; ACC_STYLE = DEFAULT_STYLE

    # One sheet per food type: column 0 full, column 1 empty.
    for kind in BOWL_KINDS:
        sheet = Image.new("RGBA", (BOWL_W * 2, BOWL_H), (0, 0, 0, 0))
        sheet.paste(draw_bowl(kind, True), (0, 0))
        sheet.paste(draw_bowl(kind, False), (BOWL_W, 0))
        sheet.save(os.path.join(outdir, f"bowl_{kind}.png"))
    manifest["bowls"] = BOWL_KINDS

    mouse_sheet = Image.new("RGBA", (MOUSE_W * 2, MOUSE_H), (0, 0, 0, 0))
    mouse_sheet.paste(draw_mouse(False), (0, 0))
    mouse_sheet.paste(draw_mouse(True), (MOUSE_W, 0))
    mouse_sheet.save(os.path.join(outdir, "mouse.png"))
    manifest["mouse"] = {"w": MOUSE_W, "h": MOUSE_H}

    for name, (w, h, frames) in {
        "ball": (BALL_W, BALL_H, draw_ball()),
        "feather": (FEATHER_W, FEATHER_H, draw_feather()),
    }.items():
        sheet = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            sheet.paste(fr, (i * w, 0))
        sheet.save(os.path.join(outdir, f"toy_{name}.png"))
    manifest["toys"] = {
        "mouse": {"w": MOUSE_W, "h": MOUSE_H},
        "ball": {"w": BALL_W, "h": BALL_H},
        "feather": {"w": FEATHER_W, "h": FEATHER_H},
    }

    with open(os.path.join(outdir, "sprites.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    scale, pad = 6, 10
    cols = max(len(f) for f in sheets.values())
    pw = cols * W * scale + pad * (cols + 1)
    ph = len(sheets) * H * scale + pad * (len(sheets) + 1)
    prev = Image.new("RGBA", (pw, ph), (0, 0, 0, 255))
    pp = prev.load()
    for y in range(ph):
        for x in range(pw):
            pp[x, y] = (30, 30, 34, 255) if ((x // 18) + (y // 18)) % 2 else (20, 20, 24, 255)
    for r, (name, frames) in enumerate(sheets.items()):
        for c, f in enumerate(frames):
            prev.alpha_composite(f.resize((W * scale, H * scale), Image.NEAREST),
                                 (pad + c * (W * scale + pad), pad + r * (H * scale + pad)))
    prev.save(os.path.join(root, "preview.png"))
    print("wrote", len(sheets), "sheets ->", outdir)
    for name, f in sheets.items():
        print(f"  {name:6s} {len(f)} frames")


if __name__ == "__main__":
    main()
