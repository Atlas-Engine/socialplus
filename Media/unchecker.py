"""Lift art off a checkerboard that was saved INTO the image.

Image generators often export "transparent" art as an RGB picture of the
checkerboard an editor would draw behind transparency. There is no alpha to
keep, so this works one out: the checker is two flat greys (about 140 and 197
here), and the art is either coloured (gold, blue) or dark (outlines).

  - a dark pixel is art, whole;
  - a grey pixel in the checker's brightness range is background;
  - between them, how COLOURED a pixel is says how much art is in it. A glow
    fading into the checker loses saturation as it goes, so saturation is the
    alpha, and the grey it was mixed with is taken back out of the colour.

    python unchecker.py "C:\\Users\\David\\Downloads\\thegoat.png" goatwords 512 128

Writes <name>.tga, uncompressed 32-bit with power-of-two sides (all the client
will load), the art scaled to fit and centred, and <name>-preview.png on the
Friends List title bar colour for checking by eye.
"""

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = 168      # the average of the two greys, for unmixing
SAT_FLOOR = 14     # saturation the checker itself reaches through JPEG noise
SAT_FULL = 70      # saturation at which a pixel is taken as all art
DARK = 105         # below this on the brightest channel, a pixel is outline


def lift(im):
    im = im.convert("RGB")
    out = Image.new("RGBA", im.size)
    src, dst = im.load(), out.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b = src[x, y]
            hi, lo = max(r, g, b), min(r, g, b)
            sat = hi - lo
            if hi < DARK:
                a = 1.0
            else:
                a = min(1.0, max(0.0, (sat - SAT_FLOOR) / (SAT_FULL - SAT_FLOOR)))
                # Bright near-white highlights inside the lettering are art too,
                # and are brighter than either checker grey.
                if hi > 225:
                    a = max(a, min(1.0, (hi - 225) / 20))
            if a <= 0:
                dst[x, y] = (0, 0, 0, 0)
                continue
            if a < 1:
                unmix = lambda c: int(max(0, min(255, (c - (1 - a) * CHECKER) / a)))
                r, g, b = unmix(r), unmix(g), unmix(b)
            dst[x, y] = (r, g, b, int(a * 255))
    return out


def main():
    path, name = sys.argv[1], sys.argv[2]
    tw, th = int(sys.argv[3]), int(sys.argv[4])
    art = lift(Image.open(path))
    # Cropped where the art is mostly opaque, not wherever any trace of glow
    # reaches: the faint haze around generated lettering is wide and tall, and
    # boxing all of it shrinks the words to half the texture.
    art = art.crop(art.getchannel("A").point(lambda v: 255 if v > 150 else 0).getbbox())

    scale = min((tw - 8) / art.width, (th - 4) / art.height)
    art = art.resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))), Image.LANCZOS)
    tex = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    tex.paste(art, ((tw - art.width) // 2, (th - art.height) // 2), art)
    tex.save(os.path.join(HERE, name + ".tga"))

    bar = Image.new("RGBA", (tw + 40, th + 20), (43, 33, 33, 255))
    bar.alpha_composite(tex, (20, 10))
    bar.save(os.path.join(HERE, name + "-preview.png"))
    print(f"{name}.tga {tw}x{th}; art {art.width}x{art.height}, filling {art.width / tw:.0%} of the width")


if __name__ == "__main__":
    main()
