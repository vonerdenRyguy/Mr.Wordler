"""Paints Letterra's land from above (the board's disc, Lantern in the middle)
into assets/globe/map_land.jpg (every harbor taken) and map_bays.jpg (every
harbor an open bay). Must follow lib/letterra/planet.dart.
Run: python tool/globe_art/make_map.py"""
import os
import numpy as np
from PIL import Image

N = 2048
rng = np.random.default_rng(7)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'globe')
os.makedirs(out, exist_ok=True)
tab = rng.random((512, 512))


def noise(x, y):
    xi, yi = np.floor(x).astype(int), np.floor(y).astype(int)
    u, v = x - xi, y - yi
    u = u * u * (3 - 2 * u)
    v = v * v * (3 - 2 * v)
    t = lambda a, b: tab[a % 512, b % 512]
    return (t(xi, yi) * (1 - u) + t(xi + 1, yi) * u) * (1 - v) + (t(xi, yi + 1) * (1 - u) + t(xi + 1, yi + 1) * u) * v


def fbm(x, y, o=4):
    r, a, s = 0, .5, 0
    for i in range(o):
        r = r + a * noise(x * 2**i + 17 * i, y * 2**i + 31 * i)
        s += a
        a *= .5
    return r / s


def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def C(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], float)


def mix(a, b, t):
    return a + (b - a) * t[..., None]


ax = 100 + (np.arange(N) + .5) / N * 300 - .5
col, row = np.meshgrid(ax, ax)
dc, dr = col - 250, row - 250
d = np.hypot(dc, dr)
lon = np.arctan2(dc, dr)
n1, n2, n3 = fbm(col / 22, row / 22), fbm(col / 7 + 50, row / 7), fbm(col / 2.2, row / 2.2 + 90, 3)


def paint(bays):
    edge = 124.4 - d  # cells inland from the sea
    if bays:
        a = np.abs((lon + np.pi / 8) % (np.pi / 4) - np.pi / 8)
        bay = np.maximum((a - np.radians(16)) * np.maximum(d, 60), 94.4 - d)
        edge = np.minimum(edge, bay)
    e = edge + (n2 - .5) * 2.2
    woods = ss(96, 93, d + (n2 - .5) * 3)
    hills = ss(65, 60, d + (n1 - .5) * 4)
    mts = ss(46, 34, d + (n1 - .5) * 5)
    cap = ss(21, 16, d + (n1 - .5) * 3)
    peak = ss(8, 5, d)
    rd = np.abs(d - 66.5 - (n1 - .5) * 2.6)
    river = ss(0, .8, 2.4 - rd)
    ridge = 1 - np.abs(2 * fbm(col / 13 + 5, row / 13) - 1)
    ridge = ridge * ridge
    h = ss(0, 6, e) * 1.2 + n1 * 2.2 * ss(3, 12, e) + woods * (n3 * 1.1 + .6) + hills * (n2 * 5 + n1 * 3)
    h = h + mts * (ridge * 15 + 3) - river * 2.5 - mts * cap * 4
    sea = mix(C('#1b70c2'), C('#2c98dd'), n1)
    sea = mix(sea, C('#4cc9e6'), ss(-13, -3, e + n1 * 5))
    sea = mix(sea, C('#a9f2ea'), ss(-4, -.9, e))
    foam = ss(-1.3, -.7, e) * (1 - ss(-.4, .2, e))
    ring = ss(.5, .2, np.abs(e + 3.2 + n2)) * .45
    sea = mix(sea, C('#ffffff'), np.maximum(foam * .9, ring))
    sea = mix(sea, C('#2383cf'), ss(136, 147, d))
    land = mix(C('#fae6ac'), C('#edcf8b'), n2)
    grass = mix(C('#9ade5c'), C('#6fc54a'), n1)
    grass = mix(grass, C('#b8e56a'), ss(.62, .78, n2))
    land = mix(land, grass, ss(3.2, 5.4, e + n2 * 2.4))
    land = mix(land, mix(C('#4ea552'), C('#2f8046'), n3), woods)
    land = mix(land, mix(C('#d2bd78'), C('#a9b55f'), n2), hills)
    land = mix(land, mix(C('#b3a8bd'), C('#887f9a'), n2), mts)
    land = mix(land, C('#ffffff'), np.maximum(ss(.55, .8, ridge) * mts * ss(40, 24, d), cap) * .95)
    land = mix(land, C('#ffe9a0'), peak)
    bank = ss(0, .8, 3.3 - rd) * (1 - river)
    land = mix(land, C('#4db9ee'), river * ss(0, 2, e))
    land = mix(land, C('#f0dca0'), bank * .8 * ss(0, 2, e))
    # Light from the screen's upper left: locally that is west and north.
    gy, gx = np.gradient(h, 300 / N)
    nr, nc = -dr / np.maximum(d, 1), -dc / np.maximum(d, 1)
    up = gy * nr + gx * nc
    east = gy * -np.sin(lon) + gx * np.cos(lon)
    sh = np.clip(1 + (.16 * east - .13 * up), .55, 1.35)
    land = np.clip(land * sh[..., None] * 1.02, 0, 255)
    img = mix(sea, land, ss(-.15, .25, e))
    return Image.fromarray(np.clip(img, 0, 255).astype('uint8'))


for name, b in (('map_land', False), ('map_bays', True)):
    paint(b).save(os.path.join(out, name + '.jpg'), quality=88, subsampling=0)
