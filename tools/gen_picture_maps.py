#!/usr/bin/env python3
"""Сборка карт-картинок из иллюстраций Fluent Emoji (MIT).

    godot --headless --path . --script res://tools/render_svg.gd    # SVG → build/svg/*.png
    python3 tools/gen_picture_maps.py                                # → maps/pic/*.png, scripts/picture_maps.gd

Каждая карта — сцена на одну тему: крупный главный объект и несколько связанных. Иллюстрации превращаются
в контурные рисунки толщиной в клетку (граница закрашенных областей). Форма карты — скруглённый прямоугольник;
за формой — сплошная стена-фон. Закрытые контуры получают проходы (кратчайший путь сквозь стены от старта),
площадка у старта свободна. Маска: 0 — квадрат, 128 — стена рисунка, 255 — за формой карты.
"""
import os
from collections import deque
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SVG = os.path.join(ROOT, "build", "svg")
OUT = os.path.join(ROOT, "maps", "pic")

# id, название, размер, старт (доли), картинки: (имя, [x, y, w, h] в долях, зеркально)
MAPS = [
    ("mountains", "Космодром", 520, 640, (0.5, 0.9), [
        ("rocket", [0.16, 0.2, 0.68, 0.56], False), ("ringed_planet", [0.1, 0.07, 0.26, 0.19], False),
        ("comet", [0.62, 0.07, 0.28, 0.19], False), ("satellite", [0.68, 0.7, 0.2, 0.16], True),
        ("star", [0.14, 0.72, 0.12, 0.1], False), ("star", [0.44, 0.08, 0.09, 0.07], False)]),
    ("ocean", "Гавань", 600, 640, (0.5, 0.92), [
        ("ship", [0.1, 0.36, 0.8, 0.46], False), ("helicopter", [0.52, 0.07, 0.36, 0.26], True),
        ("satellite_antenna", [0.1, 0.07, 0.27, 0.25], False)]),
    ("night", "Обсерватория", 720, 720, (0.5, 0.9), [
        ("telescope", [0.2, 0.24, 0.62, 0.56], False), ("crescent_moon", [0.12, 0.09, 0.22, 0.22], False),
        ("comet", [0.6, 0.08, 0.28, 0.21], False), ("ringed_planet", [0.72, 0.62, 0.18, 0.16], False),
        ("star", [0.1, 0.64, 0.12, 0.12], False), ("star", [0.44, 0.1, 0.08, 0.08], False)]),
    # темы бесконечных уровней (по кругу; на втором круге — зеркально)
    ("t_robot", "Робототехника", 600, 720, (0.35, 0.89), [
        ("robot", [0.18, 0.2, 0.64, 0.54], False), ("gear", [0.1, 0.07, 0.22, 0.18], False),
        ("nut_and_bolt", [0.7, 0.07, 0.2, 0.17], False), ("battery", [0.72, 0.74, 0.16, 0.14], False)]),
    ("t_railway", "Железная дорога", 600, 720, (0.5, 0.88), [
        ("locomotive", [0.08, 0.3, 0.84, 0.46], False), ("factory", [0.1, 0.07, 0.3, 0.24], False),
        ("gear", [0.68, 0.08, 0.2, 0.17], False)]),
    ("t_workshop", "Мастерская", 600, 720, (0.42, 0.89), [
        ("gear", [0.2, 0.2, 0.6, 0.5], False), ("hammer_and_wrench", [0.1, 0.07, 0.24, 0.2], False),
        ("nut_and_bolt", [0.7, 0.07, 0.2, 0.17], False), ("magnet", [0.72, 0.74, 0.17, 0.14], False)]),
    ("t_lab", "Лаборатория", 600, 720, (0.42, 0.9), [
        ("microscope", [0.18, 0.18, 0.62, 0.56], False), ("alembic", [0.1, 0.07, 0.22, 0.18], False),
        ("dna", [0.72, 0.07, 0.18, 0.18], False), ("atom_symbol", [0.72, 0.75, 0.17, 0.14], False)]),
    ("t_airfield", "Аэродром", 600, 720, (0.35, 0.89), [
        ("airplane", [0.12, 0.2, 0.76, 0.56], False), ("helicopter", [0.1, 0.06, 0.28, 0.2], False),
        ("satellite_antenna", [0.72, 0.74, 0.18, 0.16], False)]),
    ("t_electric", "Электричество", 600, 720, (0.5, 0.91), [
        ("light_bulb", [0.2, 0.13, 0.6, 0.62], False), ("battery", [0.1, 0.74, 0.17, 0.14], False),
        ("magnet", [0.74, 0.74, 0.17, 0.14], False), ("atom_symbol", [0.1, 0.07, 0.17, 0.14], False)]),
    ("t_orbit", "Орбита", 600, 720, (0.42, 0.89), [
        ("satellite", [0.16, 0.2, 0.68, 0.56], False), ("ringed_planet", [0.1, 0.07, 0.26, 0.19], False),
        ("comet", [0.64, 0.07, 0.27, 0.19], False), ("star", [0.74, 0.76, 0.11, 0.1], False)]),
    ("t_plant", "Завод", 600, 720, (0.6, 0.9), [
        ("factory", [0.12, 0.17, 0.76, 0.56], False), ("tractor", [0.1, 0.75, 0.24, 0.16], False),
        ("gear", [0.7, 0.06, 0.19, 0.16], False)]),
    ("t_computers", "Компьютеры", 600, 720, (0.42, 0.89), [
        ("laptop", [0.12, 0.2, 0.76, 0.56], False), ("floppy_disk", [0.1, 0.07, 0.2, 0.17], False),
        ("joystick", [0.72, 0.74, 0.19, 0.16], False)]),
    ("t_space", "Космос", 600, 720, (0.36, 0.89), [
        ("rocket", [0.2, 0.25, 0.62, 0.54], True), ("crescent_moon", [0.1, 0.06, 0.17, 0.15], False),
        ("comet", [0.64, 0.08, 0.27, 0.19], False), ("star", [0.74, 0.76, 0.11, 0.1], False)]),
    ("t_fleet", "Флот", 600, 720, (0.5, 0.9), [
        ("ship", [0.1, 0.33, 0.8, 0.46], True), ("airplane", [0.1, 0.07, 0.3, 0.22], False),
        ("satellite_antenna", [0.72, 0.07, 0.19, 0.17], False)]),
    ("t_field", "Поле и техника", 600, 720, (0.5, 0.9), [
        ("tractor", [0.1, 0.24, 0.8, 0.52], False), ("gear", [0.1, 0.07, 0.2, 0.17], False),
        ("light_bulb", [0.74, 0.06, 0.16, 0.18], False)]),
]


def in_shape(w, h):
    """Скруглённый прямоугольник — та же формула, что game.gd → _in_shape("round")."""
    ys, xs = np.mgrid[0:h, 0:w]
    px, py = xs + 0.5, ys + 0.5
    cx, cy = w * 0.5, h * 0.5
    r = min(w, h) * 0.16
    qx = np.abs(px - cx) - (w * 0.5 - r)
    qy = np.abs(py - cy) - (h * 0.5 - r)
    straight = (qx <= 0) | (qy <= 0)
    inside_box = (np.abs(px - cx) <= w * 0.5) & (np.abs(py - cy) <= h * 0.5)
    return np.where(straight, inside_box, qx * qx + qy * qy <= r * r)


def build(w, h, start, items):
    filled = np.zeros((h, w), bool)
    for name, box, flip in items:
        src = Image.open(os.path.join(SVG, name + ".png")).split()[-1]   # альфа
        bw, bh = int(box[2] * w), int(box[3] * h)
        side = min(bw, bh)
        img = src.resize((side, side), Image.LANCZOS)
        if flip:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        a = np.array(img) > 127
        x0 = int(box[0] * w) + (bw - side) // 2
        y0 = int(box[1] * h) + (bh - side) // 2
        filled[y0:y0 + side, x0:x0 + side] |= a
    # контур: закрашенная клетка, у которой есть незакрашенный сосед по стороне
    pad = np.pad(filled, 1, constant_values=False)
    edge = filled & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    void = ~in_shape(w, h)
    wall = edge & ~void
    sx, sy = int(start[0] * w), int(start[1] * h)
    ys, xs = np.mgrid[0:h, 0:w]
    wall[((xs - sx) ** 2 + (ys - sy) ** 2) <= 25] = False   # площадка у старта
    # проходы: 0-1 поиск в ширину (стена — 1, свободная клетка — 0), вскрываем кратчайший путь к каждой области
    blocked = void
    n = w * h
    INF = 1 << 30
    dist = np.full(n, INF, np.int64)
    par = np.full(n, -1, np.int64)
    s = sy * w + sx
    dist[s] = 0
    dq = deque([s])
    wl = wall.ravel()
    bl = blocked.ravel()
    while dq:
        v = dq.popleft()
        vx = v % w
        d = dist[v]
        for u in (v - 1 if vx > 0 else -1, v + 1 if vx < w - 1 else -1, v - w, v + w):
            if u < 0 or u >= n or bl[u]:
                continue
            nd = d + (1 if wl[u] else 0)
            if nd < dist[u]:
                dist[u] = nd
                par[u] = v
                if wl[u]:
                    dq.append(u)
                else:
                    dq.appendleft(u)
    reach = np.zeros(n, bool)

    def flood(a):
        q = deque([a])
        reach[a] = True
        while q:
            v = q.popleft()
            vx = v % w
            for u in (v - 1 if vx > 0 else -1, v + 1 if vx < w - 1 else -1, v - w, v + w):
                if 0 <= u < n and not reach[u] and not wl[u] and not bl[u]:
                    reach[u] = True
                    q.append(u)
    flood(s)
    opened = 0
    for v in range(n):
        if wl[v] or bl[v] or reach[v]:
            continue
        x = v
        while x >= 0 and not reach[x]:
            if wl[x]:
                # проход шириной 3 клетки: в щель в одну клетку шары попадают редко
                for oy in (-1, 0, 1):
                    for ox in (-1, 0, 1):
                        u = x + oy * w + ox
                        if 0 <= u < n and not bl[u] and abs(u % w - x % w) <= 1:
                            wl[u] = False
                opened += 1
            x = par[x]
        flood(v)
    wall = wl.reshape(h, w)
    mask = np.zeros((h, w), np.uint8)
    mask[wall] = 128
    mask[void] = 255
    bricks = int((mask == 0).sum())
    return mask, bricks, opened, (sx, sy)


def main():
    os.makedirs(OUT, exist_ok=True)
    lines = ["extends RefCounted",
             "## СГЕНЕРИРОВАНО tools/gen_picture_maps.py — не править руками.",
             "## Карты-картинки из Fluent Emoji (MIT): маска maps/pic/<id>.png (0 квадрат, 128 стена, 255 за формой).",
             "", "const PICS := {"]
    for mid, title, w, h, start, items in MAPS:
        mask, bricks, opened, st = build(w, h, start, items)
        Image.fromarray(mask, "L").save(os.path.join(OUT, mid + ".png"), optimize=True)
        lines.append('\t"%s": {"name": "%s", "w": %d, "h": %d, "start": [%r, %r], "bricks": %d},'
                     % (mid, title, w, h, start[0], start[1], bricks))
        print("%-12s %-16s %dx%d квадратов %d, проходов %d" % (mid, title, w, h, bricks, opened))
    lines.append("}")
    open(os.path.join(ROOT, "scripts", "picture_maps.gd"), "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
