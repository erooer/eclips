# Server stability comparison

## Prior observed baseline

The pre-pass runtime log contained repeated `FLLogicTicker` deadline misses while idle (`clients=0`, `worlds=8`): 308–547 ms examples at 18:13–18:20 on 2026-07-29. The same metric windows reported ordinary measured logic work around 0.2–0.4 ms, so those records indicated late thread wakeups rather than world simulation work.

The prior log configuration also used a lossless `RemotingAppender` with buffer size 1, a non-rolling `MinimalLock` file appender, and packet tracing enabled by default for most packet types.

## Stable profile, 2026-07-29 21:10:57–21:20:57

| Metric | Result |
| --- | ---: |
| Duration | 10 minutes |
| Clients | 0 |
| Stall events >=100 ms | 0 |
| Stall events >=300 ms | 0 |
| Maximum recorded wake lateness | 0 ms |
| Process CPU delta | 14.41 s |
| Working set at completion | 578,936,832 bytes |
| Private memory at completion | 1,309,421,568 bytes |
| Thread count at completion | 18 |
| Runtime-log growth | 12,866 bytes |
| Redis slow-log / latency events during spot check | none reported |
| Redis blocked clients / delayed AOF fsync | 0 / 0 |

This is an idle-only result. It confirms that the stable local runtime profile and updated ticker did not reproduce the prior logged idle stalls during this run. It does **not** validate active player persistence, inventory, portal, or combat behavior; those require the manual active-client checklist.
