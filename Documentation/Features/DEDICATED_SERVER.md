# Dedicated Server

## Option 2: Process-per-Game (Current Implementation)

Each game runs as a separate Godot process. A wrapper script or process manager
spawns one instance per game on a different port.

### Running a Server

```bash
# Headless (no GPU required)
godot --headless -- --server --port 7357 --map "res://maps/symmetric.tres" --players 2

# With password
godot --headless -- --server --port 7357 --players 4 --password mysecret

# Multiple games on one machine
godot --headless -- --server --port 7357 --players 2 &
godot --headless -- --server --port 7358 --players 4 &
godot --headless -- --server --port 7359 --players 2 --map "res://source/match/maps/BigArena.tscn" &
```

### CLI Arguments

All arguments go after `--` (Godot user args separator):

| Argument      | Default                    | Description                        |
|---------------|----------------------------|------------------------------------|
| `--server`    | —                          | Required. Enables dedicated server mode |
| `--port`      | `7357`                     | ENet listen port                   |
| `--map`       | First map in MAPS constant | Map resource path                  |
| `--players`   | `2`                        | Number of players to wait for (2–8)|
| `--password`  | (none)                     | Optional lobby password            |

### How It Works

1. `Main.gd` detects `--server` in CLI args (or `dedicated_server` export feature)
2. Redirects to `DedicatedServer.tscn` instead of the main menu
3. `DedicatedServer.gd` calls `NetworkCommandSync.host_game(port)`
4. Waits for the expected number of players to connect
5. Auto-starts the match once all players have connected
6. Shuts down when all players disconnect

### Exporting a Server Build

Use the Godot export template with `dedicated_server=true` for the target platform.
This strips rendering and produces a smaller binary suitable for headless operation.

### Process Management (Production)

For production, use a process manager to handle multiple game instances:

```bash
# systemd service template (Linux)
# /etc/systemd/system/overgrowth-rts@.service
[Unit]
Description=Overgrowth RTS Server on port %i

[Service]
ExecStart=/opt/overgrowth-rts/server --headless -- --server --port %i --players 2
Restart=on-failure

[Install]
WantedBy=multi-user.target

# Start games on ports 7357-7359
systemctl start overgrowth-rts@7357
systemctl start overgrowth-rts@7358
systemctl start overgrowth-rts@7359
```

Alternatively, a lightweight matchmaking HTTP API could spawn processes on demand
and report available ports to clients.

### Limitations

- ~50-100MB memory per process
- Each game needs a unique port
- No shared state between games (fully isolated)
- Server participates in lockstep as peer 1 but does not control any player

---

## Option 1: Relay Server (Future — Not Implemented)

A single Godot process hosts all games, acting as a command relay without
simulating any match state. This is more memory-efficient but requires
significant architectural changes.

### Architecture

```
┌─────────────────────────────────────┐
│          Relay Server               │
│                                     │
│  ┌───────────┐   ┌───────────┐     │
│  │  Room 1   │   │  Room 2   │     │
│  │ peers 2,3 │   │ peers 4,5 │     │
│  └───────────┘   └───────────┘     │
│                                     │
│  Single ENet port, room routing     │
└─────────────────────────────────────┘
```

### Required Changes

#### 1. Room-Based RPC Routing (High Effort)
`NetworkCommandSync` currently broadcasts RPCs to all connected peers. A relay
server needs to filter RPCs so commands from Room 1 never reach Room 2.

**Options:**
- Replace `@rpc` calls with manual `multiplayer.send_bytes()` + room filtering
- Use Godot's `MultiplayerAPI` customization to intercept and route calls
- Use `SceneMultiplayer` with custom `set_auth_callback()` per room

#### 2. Peer ID 1 ≠ Host (High Effort)
The codebase checks `multiplayer.get_unique_id() == 1` to mean "I am the host."
In a relay server, peer 1 is the server itself—not a player. Every authority
check needs refactoring to a "designated room host" concept:
- `NetworkCommandSync`: command broadcast, tick synchronization
- `CommandBus`: command ordering
- `Match`: state authority
- Lobby: setting changes, match start triggers

#### 3. Room Lifecycle Management (Medium Effort)
- Create/destroy rooms on demand
- Track room → peer mappings
- Handle peer disconnects (reassign room host or close room)
- Room capacity limits

#### 4. Authority Delegation (Medium Effort)
Currently the host (peer 1) handles:
- Sending state snapshots for reconnecting players
- Sharing RNG seed and match settings
- Validating lobby passwords

In a relay server, one client per room must be designated as "room authority"
to handle these responsibilities.

#### 5. Headless Match (Low Effort)
The server doesn't need to instantiate Match scenes. It only routes messages.
No 3D rendering, no game logic, no map loading needed on the relay.

### Risk Assessment

| Subsystem                | Risk   | Reason                                    |
|--------------------------|--------|-------------------------------------------|
| Peer ID 1 assumption     | High   | Pervasive across networking + game logic  |
| RPC routing              | High   | Godot RPCs have no built-in room concept  |
| Reconnection             | Medium | Currently relies on host having game state|
| Lobby system             | Medium | Assumes 1 lobby = 1 server               |
| Match simulation         | Low    | Clients unchanged, still lockstep         |
| Checksums                | Low    | Just routing, minimal change              |

### Recommendation

Build relay mode as a **separate networking layer** alongside the existing
host-client mode rather than retrofitting. Keep LAN/direct-connect mode
unchanged and add relay as an additional connection method.
