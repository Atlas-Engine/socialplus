"""Turn an image into a texture WoW will actually load.

The client has no PNG decoder. It reads .blp and .tga and nothing else, and it
wants the .tga uncompressed with power-of-two sides -- a 1290x646 image loads as
nothing at all, silently, which looks exactly like a wrong path.

    python mktexture.py "C:\\path\\to\\goat.png" goat
    python mktexture.py "...\\goat.png" goat --keep-black

What it does, in order:

  1. Reads whatever Pillow can read -- png, webp, jpg.
  2. Makes near-black transparent, unless --keep-black. Art generated on a black
     background carries that background with it, and an opaque black rectangle
     sitting in a friends list row is worse than no icon.
  3. Trims the fully transparent border, so the art fills the texture instead of
     floating in the middle of it with the useful part shrunk to nothing.
  4. Pads out to the next power of two on each side, centred, WITHOUT scaling --
     stretching to a square is what turns a wide banner into a squashed one.
  5. Writes an uncompressed 32-bit TGA beside this script.

It prints the aspect ratio and the inline-texture markup to paste into
SocialPlus_FLAIR, because the width has to be worked out from the height and
getting it wrong is what makes the art look stretched.
"""

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

# Anything darker than this on all three channels is treated as background.
# Generous, because a glow fades into black rather than stopping at it -- a
# tight threshold leaves a dark halo, which reads as a grubby rectangle.
BLACK = 24

# The longest side of the finished texture, before power-of-two padding.
#
# A TGA carries no compression, so every pixel is four bytes on disk and in
# memory whether anything looks at it or not. 256 gives a banner drawn 20 points
# tall more than ten times the detail it can show.
LONGEST = 256


def next_power_of_two(value):
    size = 1
    while size < value:
        size *= 2
    return size


def main(argv):
    if not argv:
        print(__doc__)
        return 1

    source = argv[0]
    name = argv[1] if len(argv) > 1 and not argv[1].startswith("--") else "texture"
    keep_black = "--keep-black" in argv

    global LONGEST
    if "--longest" in argv:
        LONGEST = int(argv[argv.index("--longest") + 1])

    if not os.path.exists(source):
        print("No such file: %s" % source)
        return 1

    image = Image.open(source).convert("RGBA")
    print("read      %s  %dx%d" % (os.path.basename(source), image.width, image.height))

    if not keep_black:
        pixels = image.load()
        cleared = 0
        for y in range(image.height):
            for x in range(image.width):
                r, g, b, a = pixels[x, y]
                if r <= BLACK and g <= BLACK and b <= BLACK:
                    pixels[x, y] = (r, g, b, 0)
                    cleared += 1
        print("cleared   %d background pixel(s)" % cleared)

    box = image.getbbox()
    if box:
        image = image.crop(box)
        print("trimmed   to %dx%d" % (image.width, image.height))

    # Scaled down to something an addon can ship.
    #
    # A TGA is uncompressed: 2048x512 is 4 MB for one icon, and this addon goes
    # to CurseForge. The art is drawn at roughly 20 points tall in a friends
    # list row, so a texture more than about four times that is paying for
    # detail no screen will ever show.
    if max(image.width, image.height) > LONGEST:
        scale = float(LONGEST) / max(image.width, image.height)
        image = image.resize((max(1, int(image.width * scale)),
                              max(1, int(image.height * scale))),
                             Image.LANCZOS)
        print("scaled    to %dx%d" % (image.width, image.height))

    width = next_power_of_two(image.width)
    height = next_power_of_two(image.height)

    # Centred on a transparent canvas rather than resized onto it. The texture's
    # sides must be powers of two; the ART inside it does not have to be, and
    # stretching it to fit is what would distort it.
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.paste(image, ((width - image.width) // 2, (height - image.height) // 2))

    target = os.path.join(HERE, name + ".tga")
    canvas.save(target, "TGA", compression=None)

    # Worked out rather than asked for. G: is a Drive-backed virtual volume and
    # getsize() there answered 0 for a file that had just been written and
    # verified -- the size is published a moment after the handle closes. A TGA
    # is an 18-byte header and four bytes a pixel, with no compression, so the
    # real figure needs no filesystem at all.
    print("wrote     %s  %dx%d  %.0f KB"
          % (os.path.basename(target), width, height,
             (width * height * 4 + 18) / 1024.0))

    # What to actually paste. The markup is |Tpath:height:width|t, and passing
    # only a height makes the client assume a square -- which squashes anything
    # that is not one.
    ratio = float(width) / height
    print("")
    print("  aspect %.2f : 1" % ratio)
    for h in (16, 20, 24, 32):
        print("    at height %2d  ->  |TInterface\\AddOns\\socialplus\\Media\\%s:%d:%d:0:-2|t"
              % (h, name, h, int(round(h * ratio))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
