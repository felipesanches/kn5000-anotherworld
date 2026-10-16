#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# Render the raw 320x200 Another World canvas dumps produced by probes/awtext.lua
# (build/canvas_NNNN.bin, one 16-bit little-endian RGB565 pixel per sample, straight
# from the KN7000 LCD framebuffer) into readable PNGs, upscaled so the 8x8 DRAW_STRING
# glyphs are legible.
#
# Question it answers: did DRAW_STRING actually draw the right glyphs, pixel-for-pixel?
# (The full-panel MAME snapshot shows the canvas too small to read the text.)
#
#   python3 -I render_canvas.py [--scale N] [--dir build] [canvas_*.bin ...]
# With no file list, renders every build/canvas_*.bin next to its input as *.png.
import sys, os, glob, struct

W, H = 320, 200

def rgb565_to_rgb888(v):
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)

def render(path, scale):
    from PIL import Image
    data = open(path, "rb").read()
    assert len(data) == W * H * 2, f"{path}: expected {W*H*2} bytes, got {len(data)}"
    im = Image.new("RGB", (W, H))
    px = im.load()
    for i in range(W * H):
        v = data[i * 2] | (data[i * 2 + 1] << 8)
        px[i % W, i // W] = rgb565_to_rgb888(v)
    if scale != 1:
        im = im.resize((W * scale, H * scale), Image.NEAREST)
    out = os.path.splitext(path)[0] + ".png"
    im.save(out)
    return out

def main():
    scale = 3
    dir_ = "build"
    files = []
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--scale":
            scale = int(args[i + 1]); i += 2
        elif a == "--dir":
            dir_ = args[i + 1]; i += 2
        else:
            files.append(a); i += 1
    if not files:
        files = sorted(glob.glob(os.path.join(dir_, "canvas_*.bin")))
    for f in files:
        print("rendered", render(f, scale))

if __name__ == "__main__":
    main()
