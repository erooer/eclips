# Phase 9 — Echo Dust and Forge V1

Forge V1 uses `echo_dust` as the universal salvage resource. Initial salvage is deliberately
conservative and limited to duplicate custom special items in unequipped bag slots: Eye of
the Ominous (60), Mantle of the Below (80), and Judgement (120). Equipped slots are always
rejected.

Recipes are deterministic known-base-item outputs: Eye, Mantle, and Judgement. Each consumes
Echo Dust plus its corresponding non-mark blueprint material. Marks, quest chests, stat
potions, normal gear, and ordinary consumables are not accepted recipe inputs.

`/forge` lists recipes, `/forge preview <recipe>` shows costs, `/forge salvage <bag-slot>`
salvages an eligible item, and `/forge craft <recipe>` crafts to an empty bag slot. Material
balances are checked before spending; failed later stages refund every spent material.
