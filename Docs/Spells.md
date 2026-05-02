## Spell Design System — Extended

---

### ##Base Properties##
Each base has intrinsic physical properties. These drive ALL interaction math automatically.
No lookup tables needed — outcomes are computed from property deltas.

    #Fire#
    temperature:    10   (max heat)
    moisture:        0
    density:         2
    state:           plasma
    conductivity:    7   (spreads through Air easily)
    affinity:       +8   (aggressive, outward)
    opposing_base:   Water

    #Water#
    temperature:     2
    moisture:       10
    density:         6
    state:           liquid
    conductivity:    5
    affinity:        0   (neutral direction)
    opposing_base:   Fire

    #Air#
    temperature:     4
    moisture:        3
    density:         1   (min density)
    state:           gas
    conductivity:    9   (highest — carries other elements)
    affinity:       +5   (dispersing, outward)
    opposing_base:   Earth

    #Spirit#
    temperature:     5
    moisture:        0
    density:         0   (immaterial)
    state:           immaterial
    conductivity:    6
    affinity:        0   (adaptive)
    opposing_base:   Void

    #Earth#
    temperature:     3
    moisture:        2
    density:        10   (max density)
    state:           solid
    conductivity:    2   (lowest — resists spread)
    affinity:       -8   (grounding, inward)
    opposing_base:   Air

    #Light#
    temperature:     6
    moisture:        0
    density:         0   (massless)
    state:           radiant
    conductivity:   10   (instant, infinite range)
    affinity:       +3   (revealing)
    opposing_base:   Void

    #Void#
    temperature:     0   (absolute cold)
    moisture:        0
    density:       -10   (anti-density; pulls inward)
    state:           null
    conductivity:    0   (absorbs, never propagates)
    affinity:      -10   (maximum inward pull)
    opposing_base:   Light, Spirit


---

### ##Mixed Base Casting##

    #Blend weights#
    A spell can carry 1–3 bases simultaneously with weights summing to 100%.
    Example: Fire(70%) + Air(30%) = a hot fast-moving spell with spread tendency.

    Current creator implementation:
        -Select 1–3 bases in the spell creator.
        -Selected bases are currently assigned equal weights automatically.
        -Mixed-base spells cost more than single-base spells.
        -Known synergies show generated names and blended visual colors.

    Blended property values are weighted averages of each base's properties,
    EXCEPT for some overrides:
        -If any base is Void, temperature is clamped to 0 regardless of blend weights
        -If density delta > 8 between two bases, the denser one dominates (60% minimum)
        -Conductivity uses the MAX of contributing bases, not the average
            (the most conductive element determines how the spell moves)

    #Complex spell identities#
    Mixed-base spells do NOT simply inherit all base checkboxes.
    They produce a new spell identity with its own effect profile.
    The creator displays this profile as a pentagon using:
        Burn, Force, Area, Control, Support

    These are the first implemented complex spell identities:
        Fire + Water      → Steam
            Scalding vapor cloud. Burns enemies in an area over time and obscures vision.
        Fire + Earth      → Lava
            Molten mass. Slow, heavy impact with lingering ground burn.
        Fire + Air        → Wildfire
            Fast spreading flame. Lower impact, high spread and repeated burn ticks.
        Fire + Light      → Solar Flare
            Radiant heat burst. Applies burn and blinding glare.
        Water + Air       → Frost
            Freezing mist. Chills and can freeze wet targets.
        Water + Earth     → Mud
            Dense mire. Snares targets and softens movement in an area.
        Water + Spirit    → Healing Mist
            Restorative vapor. Heals allies over time in an area.
        Air + Light       → Laser
            Focused radiant line. Extreme speed and range with blinding precision.
        Air + Earth       → Dust Storm
            Abrasive dust cloud. Blinds and deals chip damage across an area.
        Earth + Light     → Crystal
            Refracting solid magic. Defensive refraction and piercing shard behavior.
        Spirit + Light    → Radiant Aura
            Protective radiance. Passive healing with illusion-breaking light.
        Void + Earth      → Singularity
            Crushing inward gravity. Pulls targets into a dense impact point.
        Void + any other  → Null Rift
            Hostile void blend. Consumes the other base and creates a cold destabilizing field.

    #Naming rule#
    The system generates a display name from the top-2 bases by weight.
    If a known synergy exists → use the synergy name.
    Otherwise → "{dominant base} {secondary base} bolt / wave / sphere / etc."
    Example: Earth(55%) + Water(45%) sphere = "Mud Sphere"


---

### ##Collision Resolution System##

When two spell projectiles (or a spell and a surface/effect) meet,
the system combines elemental logic with waveform interference.

    #Waveform layer#
    Every moving spell has:
        amplitude = intensity x size x relevant base weight
        frequency = speed/intensity/base-count derived oscillation
        phase = dominant-base phase offset + elapsed oscillation
        coherence = how clean/stable the spell is (single-base is cleaner than mixed)

    Interference decides how much of the collision amplifies or cancels:
        phase aligned      -> constructive interference / amplification
        phase opposed      -> destructive interference / cancellation
        partial alignment  -> some energy cancels and some leaks through

    Aim still matters:
        head-on or direct projectile overlap gives the player a stronger opportunity
        to counter the incoming spell. Glancing collisions produce partial outcomes.

    Tactical intent:
        -If an enemy casts Fire, even weak Water can be the right answer because
          opposing bases create Steam and cancel Fire energy efficiently when aimed well.
        -If both sides cast Fire, it becomes a contest of amplitude, phase timing,
          aim, and spell strength. Aligned Fire can merge/amplify; opposed Fire can cancel.
        -Most direct spell collisions should visibly cancel or convert some energy at
          the contact point. A collision is usually a defensive event, not just two
          projectiles ignoring each other.
        -Full deletion is reserved for close power matches or especially clean counters.
          If one spell is clearly stronger, the collision strips away part of it and a
          weakened remnant carries through toward the original target.

    #Cancellation bias#
    The collision system should prefer partial cancellation over pure pass-through.
    Even non-opposed spells lose or convert some energy when their volumes overlap.
    The amount of cancellation is driven by:
        -relationship strength: opposed > same-base opposed phase > general collision
        -power ratio: closer powers cancel more completely
        -aim quality: head-on/direct overlap cancels more than a graze
        -waveform: opposed phase cancels, aligned phase merges/amplifies

    Remnant rule:
        If a spell wins a collision by a meaningful margin, it should not be fully
        consumed. It continues as a smaller/weaker remnant unless the matchup is a
        hard counter and the defending spell was close enough in power.

The engine then runs these checks in order:

    #Step 1 — Check opposing bases#
    If spell A contains base X and spell B contains base X.opposing_base:
        → Trigger OPPOSITION REACTION (see below)
        → Skip remaining steps

    #Step 2 — Check same-base collision#
    If spell A and spell B share a dominant base (>50% weight):
        → Trigger SAME-BASE MERGE (see below)
        → Skip remaining steps

    #Step 3 — General collision#
    No special relationship. Resolve via property comparison only.

    ---

    #Opposition Reaction#
    Used when opposing bases meet (Fire vs Water, Air vs Earth, Spirit vs Void, Light vs Void).
    Opposition reactions receive strong cancellation weighting from the waveform layer.

    Compute opposition_power for each spell:
        opposition_power = base_weight × intensity × size

    If powers are within 35% of each other:
        → MUTUAL ANNIHILATION
        → Produce a reaction effect (see Reaction Effects table)
        → Both spells are consumed

    Clean head-on aim and destructive waveform timing can widen the annihilation band
    up to roughly 50%. Glancing collisions can narrow it back toward 20%.

    If one power is outside the annihilation band:
        → DOMINANT REMNANT
        → Winning spell continues with reduced properties:
            cancellation_ratio  = loser_power / winner_power
            remaining_intensity = winning_intensity × (1 - cancellation_ratio)
            remaining_size      = winning_size      × (1 - cancellation_ratio)
            minimum_remnant     = 15-25% of original, depending on collision cleanliness
        → Reaction effect spawns at collision point, scaled by the cancelled energy
        → Losing spell is consumed
        → The remnant can still hit the other player if its remaining range/path reaches them

    #Reaction Scaling#
    Collision reactions should be representative of the spells that caused them.
    A massive Fire spell meeting a massive Water spell should create a large, forceful,
    lingering Steam Cloud. A small Fire spark meeting a small Water bolt should create
    a brief puff that fades quickly.

    Compute reaction values from the colliding spells:
        cancelled_power = min(power_A, power_B) for dominant-remnant outcomes
        cancelled_power = avg(power_A, power_B) for mutual-annihilation outcomes
        source_size     = avg(size_A, size_B)
        source_intensity= avg(intensity_A, intensity_B)
        power_ratio     = cancelled_power / expected_mid_spell_power

    Reaction effect properties:
        reaction_radius   = base_radius × source_size × sqrt(power_ratio)
        reaction_duration = base_duration × duration_scale × clamp(power_ratio, 0.4, 2.5)
        reaction_strength = base_strength × source_intensity × clamp(power_ratio, 0.5, 2.0)

    Base property influence:
        -high conductivity increases spread/radius
        -high density reduces spread but increases force/impact
        -high affinity increases outward burst
        -low/negative affinity increases lingering pull or collapse
        -high moisture increases cloud/fog lifetime
        -high temperature increases burn/scald/damage strength

    Reaction effects should decay. Very large reactions can linger and affect space,
    but they should not preserve the full power of both original spells forever.

    #Reaction Effects (spawned at collision point)#
        Fire vs Water      → Steam Cloud
            radius: high, scaled by avg size + Water moisture + Fire conductivity
            duration: medium-high, longer with Water size/intensity
            strength: scald damage/obscure scales with cancelled Fire intensity

        Air  vs Earth      → Dust Burst
            radius: high if Air is strong, compact if Earth dominates
            duration: medium, longer with Earth density/size
            strength: blind/abrasion scales with cancelled Earth density and Air speed

        Spirit vs Void     → Soul Echo
            radius: medium, pulled inward by Void affinity
            duration: medium-high, longer when Void power is high
            strength: slow/silence scales with cancelled Spirit/Void intensity

        Light vs Void      → Dark Pulse
            radius: medium-high, expands then collapses
            duration: short-medium, longer if Void dominates
            strength: darkness/light-block scales with cancelled Light intensity

        Fire vs Void       → Cold Nova
            radius: medium burst, larger when Fire intensity was high
            duration: short field, longer with Void power
            strength: chill/extinguish scales with cancelled Fire heat and Void intensity

        Water vs Void      → Absolute Zero
            radius: medium, larger with Water size/moisture
            duration: medium, longer with Void power
            strength: freeze/control scales with cancelled Water intensity and Void intensity

    ---

    #Same-Base Merge#
    Used when two spells of the same dominant base collide.
    Same-base spells do not always merge:
        aligned phase      -> merge/amplify
        opposed phase      -> cancel/annihilate by amplitude
        partial phase      -> both lose energy; stronger spell may continue as remnant

    merged_intensity = A.intensity + B.intensity × 0.6   (diminishing returns)
    merged_size      = max(A.size, B.size) + min(A.size, B.size) × 0.4

    Direction: the spell with greater opposition_power continues;
    the weaker spell's momentum is absorbed, slowing the merged result
    proportionally before it continues.
        speed_penalty = (weaker_power / stronger_power) × 0.5

    If the phase is opposed, use the same cancellation bias as opposition reactions:
    similar-power spells annihilate more often, while the stronger spell survives as
    a reduced same-base remnant when the power gap is clear.

    Special same-base bonuses:
        Fire + Fire    → +20% burn duration on merged spell
        Water + Water  → +30% push force on merged spell
        Air + Air      → +25% speed on merged spell (negates speed_penalty)
        Earth + Earth  → +40% density, -20% size (compresses rather than grows)
        Spirit + Spirit→ +50% heal intensity
        Light + Light  → +30% range, blindness duration doubles
        Void + Void    → +50% pull radius, spawns secondary pull point

    ---

    #General Property Collision (Step 3)#
    When no special relationship exists, compare properties:

        temperature_delta = abs(A.temperature - B.temperature)
        density_delta     = abs(A.density - B.density)

        If temperature_delta > 6:
            → Thermal cancellation: both spells lose energy at the contact point.
              The hotter spell may keep more of its intensity, but the cooler spell
              still removes part of it before any remnant carries through.

        If density_delta > 6:
            → Density domination: denser spell pushes lighter spell
              deflection_angle = (density_delta / 10) × 45°
              (lighter spell deflects and weakens; denser spell continues with minor loss)

        Otherwise:
            → Partial cancellation cloud at overlap point.
              Both spells lose a small-to-moderate amount of intensity/size.
              If neither drops below its survival floor, both remnants continue.


---

### ##Status Effect Interactions##

Certain base effects interact with each other on a target, distinct from spell-vs-spell collisions.

    Burn (from Fire) + Cools (from Water):
        → Extinguish: removes Burn immediately
        → If Water spell intensity > 5: also applies Wet (reduces next Fire damage by 30%)

    Burn (from Fire) + Blows (from Air):
        → Fanned: Burn ticks 50% faster (Air spreads combustion)
        → Does NOT extinguish

    Wet (from Water) + Freezing (from Water+Air):
        → Frozen: hard CC, breaks on damage > threshold

    Push (from Water) + Pull (from Void):
        → Cancels both forces; target briefly enters zero-gravity state (0.5s)

    Gravity (from Void + Earth):
        → Singularity pull. Targets inside the field are pulled toward the center.
          The center has the strongest gravity, and pull strength drops exponentially
          toward the edge of the radius.

    Frozen + Fire (incoming spell):
        → Shatter: frozen target takes ×1.5 impact damage, breaks CC instantly

    Wet + Earth (incoming spell):
        → Mired: Mud snare applied, -60% movement speed

    Blinded (from Air/Dust) + Light (incoming spell):
        → Overwhelm: blind duration extended by 50%

    Flash Blind (from Light):
        → Creates a large 3D area flash. Players and NPCs inside the flash radius
          become blinded for the spell's blind duration.

    Healing (from Spirit) + Burn (active on target):
        → Conflict: heal reduced by 40% while burn is active (cauterize tension)

    Healing (from Spirit) + Wet (active on target):
        → Amplified: heal increased by 25% (conductive medium)


---

### ##Mana Cost Formula##

The base cost formula with multi-base support:

    base_cost = Σ (base_weight[i] × intensity × size × range_factor × speed_factor)

    range_factor = range ^ 1.2            (slight superlinear)
    speed_factor = (speed / 10) ^ 2.5     (strongly superlinear — fast spells cost much more)

    For beam shape:
        range_factor = range ^ 1.8        (exponential per original spec)

    Multi-base surcharge:
        2 bases → ×1.15
        3 bases → ×1.35
        (Blending is expensive — you're doing more magical work)

    Synergy discount:
        If the blend matches a Known Synergy exactly → ×0.90
        (The universe cooperates with natural combinations)

    Charging surcharge (sphere only):
        cost_per_tick += (current_size_bonus / max_size_bonus) × base_cost × 0.3

    Current runtime implementation:
        -Spell creation credits remain the source of truth for spell complexity.
        -Mana cost is derived from credits:
            mana_cost = max(5, ceil(credits × 0.6))
        -Any spell containing Spirit has a large mana surcharge:
            mana_cost ×= 1.65
          (Healing and soul magic are powerful, so they are expensive to sustain.)
        -Beam spells drain mana continuously while held:
            mana_per_second = max(2.0, mana_cost × 0.42)
        -Charged sphere spells pay the base sphere cost when charging starts.
         Each size increase spends the difference between the previous charged cost
         and the new charged cost:
            charged_cost = mana_cost × (1 + extra_size × 0.35)
        -The player has 100 mana and regenerates 14 mana per second when not actively
         maintaining a beam or charge. Charging allows only slow trickle regeneration.
        -If the player cannot pay the cost, the spell does not cast or the charge stops growing.


---

### ##Health and Damage##

    Current runtime implementation:
        -Players have 100 health.
        -Basic caster NPCs have 80 health.
        -Projectile and beam raycasts apply spell effects to damageable bodies before
         spawning the normal impact visual.

    Spell damage is derived from spell construction values so stronger designed spells
    are more threatening in combat:

        damage = intensity × 5
               + (size - 1) × 2.5
               + (speed - 1) × speed_weight
               + mixed_base_bonus
               + selected_effect_bonus

    Damage modifiers:
        -Sphere spells use the full calculated damage on impact.
        -Beam spells apply reduced damage per impact tick.
        -Wall spells use reduced damage because they are persistent/control-oriented.
        -Burn, density, and pull increase direct damage.
        -Solar Flare (Fire + Light) uses heavily reduced direct damage because its
         blind and burn utility are already strong.
        -Healing spells trade most direct damage for health restoration.

    Water pushback:
        Water spells with the Pushes attribute apply knockback on hit.
        Push force scales with Water weight, intensity, size, and speed.
        Beam and lingering area ticks apply reduced push so they shove steadily
        rather than launching targets at full projectile force every tick.
        Players receive push as temporary external velocity.
        For multiplayer testing, any Water hit gives players a small minimum shove,
        while Push-enabled Water scales that shove higher.
        Player-cast push spells also produce reduced caster recoil when the beam or
        sphere impacts a target or surface, making Water useful for movement tests.
        The world includes a blue "PUSH TEST" rigid body near the NPC spawn. It reacts
        to any Water hit with a minimum physics impulse, and Push-enabled Water hits
        scale that impulse higher, so push can be tested independently of NPC movement.
        In multiplayer, the push test body is simulated by the server and its physics
        state is replicated to clients.
        Basic caster NPCs use the same testing rule: any Water hit gives them a
        minimum shove, while Push-enabled Water scales the shove higher. Basic casters
        use a CharacterBody3D root so their collision body and pushed body stay synced
        across repeated hits. Basic casters chase, retreat, and strafe around the player.

    Void/Earth gravity:
        Void + Earth spells create gravity instead of push. The pull direction is
        always inward toward the spell impact or lingering Singularity center.
        Gravity strength scales with intensity, size, Void/Earth weights, Pull
        Strength, and Control score. It uses exponential falloff, so actors near the
        center are pulled hard while actors near the edge feel a much weaker tug.
        Gravity impact fields use an enlarged area radius so Singularity effects can
        influence a wider part of the arena.
        Players and basic caster NPCs receive gravity as temporary movement velocity.
        Physics test boxes receive gravity as central impulses.

    Light blind:
        Light spells with Illusion, plus natural flash identities like Solar Flare
        and Laser, create a large flash AOE on impact.
        Players inside the flash receive a bright screen overlay for the blind period.
        Basic caster NPCs inside the flash stop aiming and casting while blinded, and
        their label shows the remaining blind timer.

    Healing:
        Spirit is the healing base.
        Spirit-only spells and high-support Spirit synergies restore health instead of
        dealing direct damage by default.
        Current healing synergies:
            Spirit            -> direct restoration
            Water + Spirit    -> Healing Mist
            Light + Spirit    -> Radiant Aura
        Spirit + Void does not heal because Void corrupts/suppresses the Spirit energy.
        Healing amount scales with Spirit weight, intensity, size, and Support score.
        Beams heal in smaller ticks.
        Non-beam healing spells self-cast on the player and spawn a lingering healing area.

    Death and respawn:
        -When the player reaches 0 health, casting/movement stops and a respawn timer starts.
         After 2.5 seconds, the player returns to the spawn point with full health and mana.
        -When a basic caster reaches 0 health, it disappears, stops colliding/casting, then
         respawns after 4 seconds with full health.

    Impact and reaction area damage:
        -Impact effects are no longer only visual. While they linger, they periodically apply
         reduced tick damage or healing to damageable actors inside their radius.
        -Player-created spells affect the caster too. Damage, healing, blind, push, and
         gravity from the player's own lingering impacts are applied if the player is in range.
        -Steam Cloud damage comes from the Fire/Water reaction spell that created it, so a
         larger and stronger Fire/Water collision creates a larger, longer, hotter scald zone.
        -Dust Burst, Cold Nova, Absolute Zero, Dark Pulse, Soul Echo, and same/general
         collision impacts also tick based on their reaction spell's calculated damage.
        -Area ticks use beam-style reduced damage so lingering fields are dangerous over time
         without instantly duplicating the full projectile hit.

    Current gameplay:
        -Player HUD shows health and mana.
        -When bots are enabled, each NPC caster receives three random sphere spells
         from a bot spell pool that includes Fire, Water Push, Light Flash,
         Void/Earth Singularity, and mixed-base variants for testing damage, push,
         blind, and gravity from incoming attacks.
        -Bot spell loadouts use the same shared credit budget concept as player
         loadouts: Easy bots get half the player budget, Medium bots get the player
         budget, and Hard bots get one-and-a-half times the player budget. Bots only
         cast when they have enough mana.
        -NPC casters move around the arena while maintaining casting pressure.
        -Player spells can damage or heal damageable targets.
        -Lingering impact/reaction effects damage or heal targets standing inside them.
        -Spell creator and in-game spell labels show runtime mana and damage values.


---

### ##Spell Loadout##

    Current runtime implementation:
        -The spell creator lists saved spells from user://spells.
        -Selecting a saved spell loads it into the editor for viewing or editing.
        -Saving while a saved spell is selected updates/overwrites that spell.
        -Changing the selected spell's name updates its saved file path and loadout references.
        -Saving a brand-new spell does not assign it to any loadout slot automatically.
         Players manually assign saved spells to LMB, RMB, and Shift.
        -New Spell clears the current selection and starts a fresh spell.
        -Deleting a saved spell removes its resource and clears it from any loadout slot.
        -The creator has loadout controls for assigning saved spells to LMB, RMB, and Shift.
        -Assignments are persisted in user://loadout.cfg and loaded by gameplay.
        -The player can browse saved spells with the mouse wheel.
        -Press 1 to assign the browsed spell to left click.
        -Press 2 to assign the browsed spell to right click.
        -Press 3 to assign the browsed spell to Shift.
        -Left click, right click, and Shift cast their assigned slots directly.

    Loadout limit:
        -The three assigned spells share one loadout credit budget.
        -Current loadout budget: 120 credits.
        -Assignment is rejected if the total cost of all three slots would exceed the budget.
        -In the creator, assignment buttons are disabled and unaffordable saved spells are
         shown muted when the selected loadout cannot fit them.
        -This allows multiple simple or mixed utility spells, but prevents taking three
         high-cost complex spells at the same time.

    Current HUD / creator UI:
        -Shows the browsed spell and its individual cost.
        -Shows LMB/RMB/Shift assignments and total loadout cost.
        -Shows feedback when an assignment succeeds or is blocked by the loadout limit.


---

### ##Collision Detection Priority##

For the engine implementation, evaluate in this order per frame:

    1. Spell vs Spell     (highest priority — check opposing bases first)
    2. Spell vs Effect    (spell hitting a Steam Cloud, Dust Burst, etc.)
        → Effects have a base and properties; treat as a weak spell (intensity = 1)
    3. Spell vs Surface   (terrain, walls)
        → Earth surfaces absorb Earth spells (no bounce)
        → Air spells pass through foliage (density < 2)
        → Void spells ignore most surfaces (no density interaction)
    4. Spell vs Target    (entity hit)

Current gameplay implementation:
    -World floors, walls, and obstacle boxes have physics collisions.
    -Moving sphere spells raycast/sweep along their travel path each frame.
    -On collision with world geometry, the projectile is consumed and spawns its impact effect.
    -Beam spells raycast to world geometry and repeatedly spawn impact effects while held on a surface.
    -Complex spell impact visuals use their identity profile and pentagon stats to determine radius/lifetime.
    -Moving spell projectiles now detect nearby spell projectiles and run collision resolution.
    -Opposing bases spawn a reaction effect; waveform cancellation determines whether both vanish or one continues weakened.
    -Same dominant bases use phase interference: aligned spells merge, opposed spells cancel, partial overlap weakens both.
    -General collisions compare temperature/density plus waveform interference, causing weakening, deflection, or small amplification.
    -A basic NPC caster fires Fire sphere spells at the player for collision testing.
    -Target damage/healing application is implemented for player and basic NPC casters.
    -Impact and reaction effects apply reduced area tick damage/healing while they linger.
    -Full status effect application is still pending.
