# Neotokyo server-side Sourcemod plugins

**nt_selfmute**: Allows muting player locally (finally), dampens memory leaks by setting sv_alltalk 1 and using overrides to control voice broadcasting.
*Requires funvotes-NT to work properly!*

**funvotes-NT**: stock Sourcemod script with an added forward to keep track of !votealltalk. 

**nt_ghostcapsfx**: special effects on ghost cap or end of round (ghost explodes, can also damage player) and various added sound effects while carried (requires [nt_ghostcap 1.6](https://github.com/glubsy/nt-sourcemod-plugins/blob/master/scripting/nt_ghostcap.sp)!).

**nt_jumpsounds**: adds a different jumping sound effect to each class, can enable additional custom sounds too.

**nt_weapontweaks**: prevents SRS quick switch exploit, adds recoil, screen shaking and randomized tracers to some guns.

**nt_specvisions**: adds vision modes availability to spectators and dead players.

**nt_specbinds**: binds number keys to 10 alive players for convenient camera switching.

**nt_restartfix**: Agiel's plugin, rewritten to handle neo_restart_this 2 which resets only current round, reverting player scores as well.

**nt_slowmotion**: simulates slow motion effect once last man standing dies.

**nt_supportknife**: gives a knife to support classes on player spawn, and switches back to first weapon slot.

**nt_cyborgvision**: !vision to disable cyborg vision (which is enabled by default).

**nt_console**: !console to open console, and kill command blocker.

**nt_randomserverpassword**: sets a random password on request (public command) and resets to the default password (line 66) after the last player quits the game.

**nt_unstuck**: !stuck command to nudge a player in a given direction.

**nt_entitytools**: various tools to manipulate entities in game. Allows Admins to spawn props. Mostly for testing purposes.

**nt_props**: allows player to spawn various props depending on their score.

**nt_sniper_laser**: adds laser beam and laser dot to sniper rifles.

**nt_highlights**: highlights player_hurt events for spectators by tracing coloured beams matching damage done.

**nt_pain_sfx**: sound effects emitted when a player gets hurt.

**nt_cloak**: adds a one-time use cloak for support class, which gets turned off as soon as the player gets damaged.

**nt_ghostpos**: anti-griefing measure that checks for ghost position on certain maps, teleports it back to valid coordinates + anti ghost-hopping.

**nt_visualmarker**: places a marker in the world to indicate a point of interest to your team mates, like a spotted opponent.

**nt_detpack_tweaks**: destructible detpacks, invisible at a distance, remote can be dropped on death, detpack can be retrieved with +use and dropped on death.

**nt_visionglow**: places a glowing halo on player's head when using a vision mode.

**nt_gmute**: blocks haters and toxic players from communicating with less weird people.

Donger model here: https://www.mediafire.com/?6y352ceczvs3oc1

~~**Funvotes-NT**: Modified Sourcemod default "funvote" plugin with a specific neotokyo public vote to restart the game. Obsolete (merged in nt_votes.sp for nt_teamdeathmatch)~~

Notes: SourceMod offsets are often wrong for Neotokyo, which makes it very hard to troubleshoot and develop plugins for it.
