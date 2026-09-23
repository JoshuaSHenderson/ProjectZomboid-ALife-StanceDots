# A-Life Stance Dots

Client-side add-on for **Project A-Life [ALIFE NPCS]** (Workshop `3803984183`, mod id `ProjectALifeNPCs`).
Draws a dot over every A-Life NPC's head:

| Dot | Stance | Meaning |
| --- | --- | --- |
| 🟢 green | `friendly` | will not attack you |
| 🟡 yellow | `neutral` | leaves you alone unless provoked |
| 🔴 red | `careful` / `hostile` | A-Life's combat code treats both as hostile |

## How A-Life distinguishes friendly from hostile

The stance is **per-actor and per-player**, not a property of the spawned
group alone. `ProjectALife.Relations.playerStance(actor, player)` in
`media/lua/server/ProjectALife/AI/ALifeRelations.lua` is the authority; it
resolves in this order (first hit wins):

1. `actor.memory.hostileOverride == true` → hostile (admin / scripted force).
2. `actor.memory.hostileToPlayerKeys[playerKey]` → hostile to *that* player only.
3. `actor.memory.hostileOverride == false` → friendly, and reputation is ignored.
4. `actor.memory.spawnStance` — the stance the encounter/spawn authored
   (`friendly` / `neutral` / `careful` / `hostile`).
5. Faction default from the catalog: `faction.relations.player`
   (`allied`→friendly, `suspicious`→careful), else
   `faction.spawn.friendly == true` → friendly, otherwise hostile.
6. Earned reputation — `ProjectALife.Reputation` records a faction as hostile
   once you attack, kill or provoke it, and that override wins over 4 and 5.
7. Timed softeners: `carefulPlayerKeys` pushes neutral/friendly to careful,
   `tolerateUntil` pulls careful back to neutral, and an active robbery or
   `robberyTruce` suppresses hostility for its duration.

NPC-vs-NPC hostility is a different call, `Relations.status(source, target)`:
same `factionId`, same `groupId`, same `outpostId` or a support link means
friendly; otherwise faction `relations` tables, then bloc rules, then the
`spawn.friendly` flags on both sides.

### Getting at it from the client

* A-Life NPCs are **zombie shells**, so they are in `getCell():getZombieList()`.
* Each shell carries `ProjectALifeUID` / `ALifeUID`, plus `ProjectALifeFactionId`,
  in its mod data and game variables.
* The actor record for a uid is on the client in
  `ProjectALife.Executor.mirror.records[uid]` (the server streams full records
  and the faction definitions it needs via `ALifeMirrorTransport`), and in
  singleplayer also in `ProjectALife.ActorRegistry.read(uid)`.
* Reputation overrides reach the client as the `reputationSync` server command,
  cached in `ProjectALife.StatusStore.reputation`.

So this mod calls `Relations.playerStance` when it is loaded (singleplayer,
where server Lua shares the state) and falls back to reproducing steps 1–6 from
the mirrored record, the network faction catalog and the reputation sync on a
multiplayer client. The timed truces in step 7 are not replicated — they do not
survive the trip to the client.

## Install

Copy `ALifeStanceDots/Contents/mods/ALifeStanceDots` into
`%UserProfile%\Zomboid\mods\`, then enable **A-Life Stance Dots** after
Project A-Life in the mod list. It is client-side only; no server changes needed.

## Tuning

`ALifeStanceDots.settings` in
`42/media/lua/client/ALifeStanceDots/ALifeStanceDots.lua`:

| Key | Default | Notes |
| --- | --- | --- |
| `headHeight` | `1.15` | tiles above the NPC's feet — raise if the dot sits on the hair |
| `size` | `12` | dot size in UI pixels |
| `alpha` | `0.9` | |
| `range` | `30` | tiles from the player |
| `requireVisible` | `true` | hide dots for NPCs behind walls |

## Test

```
lua tests/stance_spec.lua
```

Stubs the A-Life globals and checks the stance priority order.
