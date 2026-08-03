# Ominous Below environment polish review

The existing candle/torch candidates are `Wall` objects. Adding them to walkable tiles would change collision and violate the non-gameplay constraint. No unverified decoration object was added automatically.

The authored map already uses the Ominous ground resource and keeps its active objectives isolated. Future visual additions must be existing, client-embedded, non-blocking static resources, placed off the traversal route, then checked with `Test-OminousBelow.ps1`.
