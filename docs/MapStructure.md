# Map structure

`.jm` files are JSON maps with integer `width`/`height`, a compressed base64 tile stream, and a dictionary. Each decoded tile indexes the dictionary; dictionary entries may provide ground, objects, and regions. Entry zero is commonly intentional void/black space in legacy maps, so the broad validator records it as a warning rather than corrupting or rewriting maps.

The map validator checks bounds, compressed length, dictionary bounds, object references, region syntax, and placed spawn regions. It reports static limitations such as dynamic gates and runtime-created objects instead of attempting to simulate them.
