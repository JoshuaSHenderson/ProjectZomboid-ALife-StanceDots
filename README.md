# A-Life Stance Dots

Client-side add-on for **Project A-Life [ALIFE NPCS]** (Workshop `3803984183`, mod id `ProjectALifeNPCs`).
Draws an icon over every A-Life NPC's head. Red is **only** for people who
will attack you.

| Icon | Status | Meaning |
| --- | --- | --- |
| red crossed swords | `hostile` | hostile to you, or attacking you / your people right now |
| orange warning triangle | `careful` | wary: won't shoot first (A-Life 1.4 fairness), but don't push it |
| yellow dot | `neutral` | leaves you alone unless provoked |
| green dot | `friendly` | will not attack you |
| green shield | `allied` | allied faction, or an allied crew (Jeem standing) |
| blue star | `companion` | in your party, walking with you, or an allied crew following you |
| blue house | `resident` | lives at a base you manage (Jeem residents) |

Priority, first hit wins: hostile → companion → resident → allied → stance.
A companion or resident who turns on you goes red.

Works with **Project A-Life 1.4.x** and, optionally, **Project A-Life - Jeem
Extension** (`ProjectALifeJimmy`), which supplies residents, crew allies and
"attacking your people".

## How A-Life distinguishes friendly from hostile

The stance is **per-actor and per-player**, not a property of the spawned
group alone. `ProjectALife.Relations.playerStance(actor, player)` in
`media/lua/server/ProjectALife/Decisions/ALifeRelations.lua` is the authority; it
resolves in this order (first hit wins):

1. `actor.memory.hostileOverride == true` → hostile (admin / scripted force).
2. `actor.memory.hostileToPlayerKeys[playerKey]` → hostile to *that* player only.
3. `Party.friendly` — you joined their group → friendly.
4. Baseline: `actor.memory.spawnStance`, else the faction's word toward players
   via `RelationLayers.towardPlayer` (`relations.player`, profession shifts,
   else `spawn.peaceable` → friendly, otherwise hostile); first contact can
   also seed a personal reputation.
5. `hostileOverride == false` → friendly.
6. Earned reputation (`Reputation.recordedStatus`): hostile always wins;
   friendly / careful / neutral replace the baseline.
7. Timed softeners: `carefulPlayerKeys`, `tolerateUntil`.
8. **Fairness** (`Fairness.stanceFor`): a hostile NPC that may not open fire
   first is reported as `careful`. That is why careful is orange, not red.

Whether an NPC will actually shoot is `Relations.hostileToPlayer` (truces,
robberies, standoffs, fairness, grudges, ordered hunts). This mod paints red
when either says hostile, or when the NPC is in combat targeting you.

NPC-vs-NPC hostility is a different call, `Relations.status(source, target)`:
same `factionId`, same `groupId`, same `outpostId` or a support link means
friendly; otherwise faction `relations` tables, then bloc rules, then the
`spawn.peaceable` flags on both sides.

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

So this mod calls `Relations.playerStance` / `hostileToPlayer` /
`Party.friendly` when they are loaded (singleplayer and host) and falls back to
steps 1, 2, 4–6 from the mirrored record, the shared `RelationLayers`, the
network faction catalog and the reputation sync on a multiplayer client.
Party membership, personal reputation, fairness and timed truces stay
server-side, so on an MP client a party member shows by faction stance and a
"careful" fairness NPC may show red. `walkWith` escorts and Jeem residents /
allies do reach the client.

## Install

Copy `ALifeStanceDots/Contents/mods/ALifeStanceDots` into
`%UserProfile%\Zomboid\mods\`, then enable **A-Life Stance Dots** after
Project A-Life in the mod list. It is client-side only; no server changes needed.

## Options

Sandbox options, page **A-Life Stance Dots** (new game, or Admin → Sandbox
Options on a running server; synced to every client):

| Option | Default | Notes |
| --- | --- | --- |
| Marker style | Icons | **Dots**: one colour per status (allied dark green, resident light blue). **Icons**: the shapes above |
| Marker height (tiles) | `1.15` | 0.5–3.0 above the NPC's feet |

## Tuning

`ALifeStanceDots.settings` in
`42/media/lua/client/ALifeStanceDots/ALifeStanceDots.lua`:

| Key | Default | Notes |
| --- | --- | --- |
| `icons` | `true` | fallback when the sandbox option is absent |
| `headHeight` | `1.15` | fallback when the sandbox option is absent |
| `size` | `16` | icon size in UI pixels |
| `alpha` | `0.9` | |
| `range` | `30` | tiles from the player |
| `requireVisible` | `true` | hide icons for NPCs behind walls |
| `cacheMs` | `500` | how long one NPC's status is reused |

Icons are generated by `python tools/make_icons.py` (Pillow).

## Test

```
lua tests/stance_spec.lua
```

No Lua on the box? `python -c "import lupa; lupa.LuaRuntime().execute(open('tests/stance_spec.lua').read())"`.
Stubs the A-Life / Jeem globals and checks the status priority order.
