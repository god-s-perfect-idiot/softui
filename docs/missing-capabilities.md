# SoftUI capabilities — shipped vs gaps

Legend: **[shipped]** available now · **[demo]** covered by a desktop/SoftShell demo · **[gap]** still missing

---

## Shipped this round

| Capability | Host ABI / surface | Demo / app |
|------------|-------------------|------------|
| Wall clock + TZ | `host_time_wall_ms`, `host_time_tz_min` | **Clock** |
| PCM audio out | `host_audio_queue`, `host_audio_stop` | **Music** (s16le synth) |
| SoftUI raw image | SoftFS `logo.simg` (SIMG) | **Image** |
| Host image decode | `host_image_decode` (async pending) | **Image** (`sample.png`) |
| suigui on SoftUI FB | `host_sui_paint` bridge | **Calc**, **Hello** |
| Multitasking tray | GUI sessions (max 6) | **home** / tray / **exit** |

### Desktop apps (17)

Shell · Clock · Cursor · Keys · Image · Music · Paint · UIKit · Colors · Text · Donut · Plasma · Stars · Cube · Fire · **Calc** · **Hello**

SoftFS factory image also packs: `logo.simg`, `sample.png`, `calculator.sui`, `hello.sui`, plus SoftASM demos.

### Multitasking behavior

- Launching an app adds/focuses a session (up to 6).
- **home** — return to desktop; sessions stay in the bottom tray.
- Tray tap — switch focus / re-enter that app.
- **exit** — end the focused session; focus another or return to desktop.

---

## Remaining gaps

### Time
| Capability | Status |
|------------|--------|
| Wall clock | **[shipped]** |
| `sleep` / alarms / scheduled wake | **[gap]** |

### Input
| Capability | Status |
|------------|--------|
| Keyboard + pointer | **[shipped]** |
| Multi-touch / gamepad / clipboard | **[gap]** |

### Audio
| Capability | Status |
|------------|--------|
| PCM queue (s16le) | **[shipped]** |
| Mic / capture / streaming sync | **[gap]** |

### Graphics / media
| Capability | Status |
|------------|--------|
| SIMG + host PNG decode | **[shipped]** |
| In-guest PNG (no host) / video | **[gap]** |
| Scrolling viewports | **[gap]** |

### UI / apps
| Capability | Status |
|------------|--------|
| Host-bridged suigui (Calc/Hello) | **[shipped]** |
| In-guest Zig suigui runtime | **[gap]** (independence / offline hosts) |
| Files / Settings apps | **[gap]** |
| Background tick while unfocused | **[gap]** (switch re-enters; no parallel ticks) |
| Notifications | **[gap]** |

### Process / net
| Capability | Status |
|------------|--------|
| SoftFS CRUD + sync | **[shipped]** |
| `spawn` / `kill` / `ps` | **[gap]** |
| Sockets / HTTP | **[gap]** |

---

## Suggested next

1. Background ticks for unfocused sessions (music keeps playing in tray).
2. Files app (SoftFS browser) + Settings (`kinfo` / colors).
3. In-guest suigui subset (drop host bridge dependency).
4. Clipboard + sleep Host ABI.

See also: [softshell.md](softshell.md), [host-abi.md](host-abi.md), [sdk/docs/roadmap.md](../sdk/docs/roadmap.md).
