##Gameplay Overview##
Divided into 2 sections:
    0. Main menu -> choose Spell Creator, Play, or Exit
    1. Spell creation -> use Spell definitions to create custom spells to bring into the world
    2. Fight in a PvPvE environment with those spells to achieve some goal

##Main menu##
On load, the app opens a main menu with:
    -Spell Creator: opens the spell creation UI
    -Play: opens Create / Join options
    -Fullscreen / Windowed: toggles fullscreen display
    -Exit: closes the app

The game targets a 1920x1080 viewport. The window is resizable and the UI scales
with the window while the playable view expands to fit larger or fullscreen
resolutions. F11 toggles fullscreen from the main menu or while playing.

Create hosts an ENet server on port 24567 and joins it as the host player.
Before hosting, Create opens host settings:
    -Bots: on/off
    -Number of bots: enabled only when Bots is on
    -Bot difficulty: Easy, Medium, Hard; enabled only when Bots is on
When Bots is off, no NPC casters spawn. When Bots is on, the server spawns the
chosen number of NPC casters.
Dedicated servers can change bot settings while running by appending commands to
the server command file. Supported commands are:
    -status
    -bots on
    -bots off
    -bots <0-12>
    -bot_count <0-12>
    -bot_difficulty <Easy|Medium|Hard>
On Fly, the command file is /tmp/fp-mager-commands.txt. For example:
    fly ssh console --app fp-mager --command "sh -lc 'echo bots off >> /tmp/fp-mager-commands.txt'"
    fly ssh console --app fp-mager --command "sh -lc 'echo bot_count 4 >> /tmp/fp-mager-commands.txt'"
From Windows, Scripts\server_command.bat wraps that Fly command:
    Scripts\server_command.bat bots on
    Scripts\server_command.bat bot_difficulty Hard
Join asks for a server address and port, then connects to that hosted game.
For internet play, the host must allow/forward UDP port 24567, or the selected
join port, through their firewall/router.
The spell creator has a Back button that returns to the main menu.
The in-game pause menu has Resume and Main Menu. Main Menu exits the current
game world and returns to the app's main menu.
The in-game pause menu also has Spell Creator. Opening it removes that player
from the active world, shows the creator as an overlay, and respawns the player
back into the same session when Back is pressed.

##Multiplayer##
Online multiplayer uses Godot ENet networking.
    -Create starts the server and loads the normal world with the NPC caster.
    -Join connects as a client and requests the current world/player state.
    -Players are spawned by network peer ID so each connected player has a stable
     replicated player node.
    -The server assigns each player the first available colour from a four-colour
     pool: blue, red, green, then yellow. Colours stay with a peer while they are
     temporarily in the spell creator and are freed when that peer disconnects.
    -The server-spawned NPC caster is replicated to clients. Its AI and combat logic
     run on the server, with position/health/blind state synced outward.
    -NPC casters use a reserved dark magenta body and bright magenta label colour,
     outside the player colour pool.
    -Each spawned NPC caster receives three random spells from the bot spell pool and
     cycles those spells while attacking.
    -Bot difficulty controls spell budget and casting cadence:
        Easy: total assigned spell cost up to 60 credits, casts every 5 seconds if it has mana
        Medium: total assigned spell cost up to 120 credits, casts every 3 seconds if it has mana
        Hard: total assigned spell cost up to 180 credits, casts as soon as it has enough mana
    -Only the local player owns camera, HUD, input, and menu controls.
    -Movement is sent from clients to the server and replicated to other clients.
    -Player combat state such as health, mana, death, respawn, and blind timers is
     replicated from the server through the world scene after authoritative hits.
    -Client self-cast spells spend mana immediately for responsiveness, then the
     server spends the same self-cast mana and sends back authoritative combat state
     so the HUD does not snap back to stale mana.
    -Local clients ignore small alive-position corrections from combat state, so
     self-heal mana/health updates do not briefly freeze movement. Large corrections
     such as death/respawn still snap to the server position.
    -Server combat state also includes external movement velocity, so authoritative
     Water push, caster recoil, and Void/Earth gravity impulses are applied on the
     owning client instead of only on the server copy.
    -Server-owned physics test objects, such as the blue push test box, replicate
     their transform and velocity to clients after push/gravity impulses.
    -Projectile casts are requested by clients, spawned by the server through the
     world scene, and replicated to clients for predicted visuals.
    -The casting client spawns a local predicted projectile immediately, then skips
     the matching server visual when it is echoed back. Echo suppression uses both
     the source peer id and a short-lived cast fingerprint so the client does not
     see its own projectile twice if peer-id matching is late or inconsistent.
    -Client projectile prediction performs visual-only collision/impact feedback.
     Damage and lingering area effects are only applied from server-authoritative
     projectile/effect logic.
    -Server projectile impacts are broadcast back to clients as visual-only impact
     effects so clients see verified collisions.
    -Server beam, projectile, and spell-collision impacts are broadcast as
     visual-only effects to clients, including their 3D effect labels. Self-cast
     healing effects use their own self-effect RPC path to avoid duplicate visuals.
    -Clients that join while an impact/reaction effect is still active receive that
     effect with its elapsed age so lingering fields such as Singularity remain visible.
    -NPC projectile attacks use the same server-spawned projectile replication path.
    -Projectile collision, projectile damage, and beam tick damage are authoritative
     on the server.
    -Death and respawn timers are server-authoritative. Clients can display the timer,
     but the server sends the final respawn state.
    -Fall damage is applied when a player lands after falling more than 5 meters.
     Damage scales by roughly 18 health per meter beyond the safe height, so a
     sufficiently high fall can instantly kill a full-health player.
    -When a player opens the spell creator from the in-game menu, the server despawns
     their player body for all peers. Closing the creator requests a fresh spawn so
     loadout changes are picked up by the new player instance.
    -Saved spell resources are loaded with cache bypassing when returning to gameplay,
     so edited spells and loadout assignments use the latest saved data.
    -After respawn, the server briefly ignores stale client movement packets and
     immediately re-broadcasts the respawn transform so remote views snap to the
     grounded spawn position.
    -Clients continue sending transform updates while the in-game menu is open, and
     send a stopped transform on focus loss, so alt-tab/menu states do not leave
     other peers seeing stale airborne poses.
    -Player transform packets are sent on a fixed 30 Hz timer and include timestamps.
    -Remote players keep a small snapshot ring buffer and render about 100ms behind
     the newest state, interpolating between snapshots instead of snapping to every
     packet.
    -NPC casters use the same style of client-side snapshot interpolation, with a
     slightly larger buffer because their server sync rate is lower than players.
    -If the buffer runs dry, remote players use capped dead reckoning from the latest
     position and velocity for up to 200ms.
    -Each remote stream estimates a small clock offset from packet timestamps so the
     interpolation buffer can line up peer times without a full clock-sync service yet.
    -Beam visuals are replicated separately from beam damage. The casting player draws
     their beam immediately, while the server relays visual-only beam start/update/stop
     messages to the other peers.

##Spell creation##
UI should dynamically update to show what the spell will look like in the characters hands / body (i.e. growing larger as its size is increased)
UI controls show all lock when credits per spell are all used.
Spells should divided into:
Simple -> Less than x cost
Complex -> Greater than x cost
A player can bring in x simple and y complex spells into the game

##Game##
Player equips their spells (or predefined layout)
Player navigates through a level where there are npc's and uses their spells to fight them.
Players fight other players to take something from them
