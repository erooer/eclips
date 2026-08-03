# The Ominous Below type IDs

`0xF900` through `0xF920` are reserved after scanning every existing server XML resource.
The range contains the portal/key, all encounter entities, completion objects, marks, and themed items.
`scripts/Test-TypeIdCollisions.ps1` enforces that this allocation remains collision-free.

| Range | Use |
| --- | --- |
| F900-F901 | Portal and key |
| F902-F909 | River section and Ferryman |
| F90A-F911 | Prison section and Veyra |
| F912-F919 | Abyss section, final boss, completion/return |
| F91A-F920 | Marks and themed rewards |
