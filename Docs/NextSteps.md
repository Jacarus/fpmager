# MagicFPS Next Steps

> Pick-up notes for future work on `C:\Code\Games\Godot\MagicFPS\fp-mager`.
>
> Current repo: https://github.com/Jacarus/fpmager
>
> Last known good branch: `main`
>
> Last known pushed commit when this file was created: `ab79431 Revert "Add SpellDefinition characterization tests"`

## Current State

The project is a Godot 4.6.2 Mono multiplayer magic FPS prototype written in GDScript.

The codebase currently has:

- 13 GDScript files
- roughly 5,900 lines of GDScript
- no C# source files yet
- a working Godot headless startup check
- a focused spell network codec test

Important recent work:

- The project was initialized as a Git repo and pushed to GitHub.
- Spell network serialization was extracted into `Scripts/SpellNetworkCodec.gd`.
- `Scenes/Player/Player.gd` and `Scenes/World/World.gd` now use the shared codec instead of duplicated spell dictionary conversion.
- The broader `SpellDefinition` characterization tests were intentionally reverted because spell costs, mana, and abilities are still in active design.

## Current Recommendation on C#

Do not convert the full project to C# yet.

Reasoning:

- The current multiplayer risks are mostly architecture and authority-boundary problems, not GDScript performance problems.
- Spell costs, mana, effects, and abilities are still being actively changed.
- A full C# rewrite now would slow iteration and make every gameplay tweak require more compile/interoperability work.
- GDScript is good for rapid Godot gameplay iteration.

Revisit C# later for stable, high-value systems such as:

- spell calculation and validation
- server-side cast/loadout validation
- authoritative combat simulation
- projectile/effect resolution
- data-heavy or CPU-heavy systems

A future migration should be incremental, not all-at-once.

## Immediate Priority

Continue refactoring and hardening the multiplayer architecture while keeping gameplay iteration fast.

The safest next move is still step 4 from the earlier direction: harden multiplayer trust boundaries.

## Suggested Next Steps

### 1. Keep Spell/Mana/Ability Iteration Flexible

Goal: avoid locking unstable gameplay numbers behind brittle tests too early.

Do:

- Continue editing `Scripts/SpellDefinition.gd` and spell UI behavior freely.
- Avoid exact-value tests for credit cost, mana cost, damage, healing, blind duration, gravity force, etc. until those rules are settled.
- If tests are needed during this phase, prefer broad invariants:
  - mana cost is never below minimum
  - invalid spells cannot be cast
  - healing spells do not deal damage
  - void + earth spells are recognized as gravity spells
  - serialization preserves fields

Avoid for now:

- exact expected values for unstable formulas
- snapshot tests of all spell numbers
- tests that make every balance tweak feel like a regression

Relevant files:

- `Scripts/SpellDefinition.gd`
- `Scenes/SpellCreation/SpellCreationUI.gd`
- `Docs/Spells.md`

### 2. Harden Client-to-Server Cast RPCs

Goal: clients should send intent, not authoritative spell/projectile data.

Current concern:

`Scenes/Player/Player.gd` still has client-to-server RPCs where clients send rich spell data, origin, direction, and/or self-effect data.

Relevant methods/areas:

- `_server_beam_tick`
- `_server_cast_projectile`
- `_server_cast_self_effect`
- local cast methods that call `rpc_id(1, ...)`
- loadout state used by server-side validation

Desired direction:

- Client sends:
  - spell slot index
  - cast action type
  - aim direction/input intent
- Server validates:
  - sender owns the player
  - sender has that spell equipped
  - spell is valid and affordable
  - mana/cooldown allows cast
  - origin is derived from server-side player state, not trusted from client
  - direction is clamped/sanity-checked
- Server spawns projectiles/effects and broadcasts results.

Suggested small tasks:

1. Add helper methods in `Player.gd` for server-side loadout lookup by slot.
2. Change one cast path, probably projectile casting, from full `spell_data` to slot-based intent.
3. Keep the old path only temporarily if needed for compatibility while refactoring.
4. Verify with a host/client manual test.
5. Repeat for beam ticks and self effects.

Do not attempt all RPC changes at once.

### 3. Extract Player Networking Into a Smaller Component/Helper

Goal: reduce `Scenes/Player/Player.gd`, which is still the largest risk file.

Current issue:

`Player.gd` handles too many responsibilities:

- input
- movement
- camera
- health/death/respawn
- HUD updates
- spell loadout
- casting
- multiplayer RPCs
- state sync

Suggested extraction order:

1. `Scripts/PlayerLoadout.gd` or `Scenes/Player/PlayerLoadout.gd`
   - loadout slots
   - slot cost calculation
   - equip/remove spell helpers
   - save/load helpers if appropriate
2. `Scenes/Player/PlayerNetworking.gd`
   - state sync helpers
   - sender validation helpers
   - cast intent validation helpers
3. `Scenes/Player/PlayerCombat.gd`
   - health/damage/death/respawn helpers
   - self effects
   - mana/cast cooldown helpers
4. `Scenes/Player/PlayerMovement.gd`
   - movement constants and movement update logic
   - camera pitch/yaw helpers

Keep each extraction small and test/launch after each one.

### 4. Add a Lightweight Test Runner Script

Goal: make checks easy to run without remembering commands.

Create something like:

- `Scripts/run_godot_tests.bat` for Windows, or
- `Scripts/run_godot_tests.sh` for WSL, or both.

Current known commands:

```bash
/mnt/c/Tools/Godot/godot.exe --headless --path . --script Tests/test_spell_network_codec.gd
/mnt/c/Tools/Godot/godot.exe --headless --path . --quit-after 2
```

Potential future test runner behavior:

- run every `Tests/test_*.gd` script
- fail fast if any test exits nonzero
- run headless startup check after script tests

Keep exact balance tests out until spell numbers are stable.

### 5. Add Stable Invariant Tests Only

Goal: improve safety without freezing balance.

Good near-term tests:

- `SpellNetworkCodec` round-trip stays working.
- Empty spell network data creates a safe fallback spell.
- A spell with no base element and no shape is invalid.
- A healing spell reports zero damage.
- A non-healing spell reports zero healing.
- A non-push spell reports zero push force.
- A non-gravity spell reports zero gravity force.
- Server validation rejects invalid sender/spell slot/cast intent.

Avoid exact numeric tests for:

- mana costs
- credit costs
- spell damage
- healing amount
- blind duration/radius
- gravity falloff
- beam tick scaling

### 6. Continue SpellCreationUI Cleanup Later

Goal: reduce the other large file once player/networking risk is lower.

`Scenes/SpellCreation/SpellCreationUI.gd` is still around 1,500 lines.

Potential future split:

- spell builder state/model
- UI construction
- preview rendering
- loadout panel
- validation/cost display
- save/load UI

Suggested approach:

- wait until spell rules are more settled
- extract non-visual state first
- keep UI scene behavior unchanged

### 7. Document Final Spell Design Once Stable

Goal: make future tests and balancing easier.

Update:

- `Docs/Spells.md`
- `Docs/Gameplay.md`

Include:

- final element list
- intended synergies
- spell shape rules
- mana/cost philosophy
- expected ability categories
- what server should validate
- what client is allowed to request

Once documented, add exact-value tests only for rules that are genuinely stable.

## Verification Commands

Use Windows Git from WSL for this repo:

```bash
"/mnt/c/Program Files/Git/cmd/git.exe" status --short --branch
"/mnt/c/Program Files/Git/cmd/git.exe" log --oneline --decorate -5
```

Use the installed Godot executable:

```bash
/mnt/c/Tools/Godot/godot.exe --headless --path . --quit-after 2
/mnt/c/Tools/Godot/godot.exe --headless --path . --script Tests/test_spell_network_codec.gd
```

Expected currently:

- Git status clean on `main...origin/main`
- Godot startup prints only the Godot banner and exits 0
- codec test prints `test_spell_network_codec: OK`

## Suggested Commit Discipline

For future work:

- make one safe change at a time
- run Godot startup and relevant tests
- commit each completed slice
- push after each safe slice

Example commit sequence:

```bash
"/mnt/c/Program Files/Git/cmd/git.exe" add <files>
"/mnt/c/Program Files/Git/cmd/git.exe" commit -m "Refactor player loadout helpers"
"/mnt/c/Program Files/Git/cmd/git.exe" push
```

## Recommended Next Pick

If continuing from here, start with:

1. Harden one cast RPC path so the client sends spell slot intent instead of full spell data.
2. Keep the change small and reversible.
3. Run a local Godot startup check and the codec test.
4. Manually test host/client casting if possible.
5. Only then repeat for other cast paths.
