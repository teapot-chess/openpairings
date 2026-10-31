# hall-link-v1

The hall link, version 1: how the hall programs that run on a hall PC -
Nunki (the announcer) and Polis (the print station) - join a tournament in
OpenPairings and keep a line open to it, and how every hall app, Manubrium
(the phone app) included, is paired with a server.

The server half of the line is not in this repository: it is the plugins
`openpairings_nunki` and `openpairings_polis`, kept in the Nunki and Polis
repositories and compiled into OpenPairings' hosted edition. The contract
lives here because OpenPairings is the server, and because one copy is the
point: the two hand-written protocol documents it replaces had already
drifted apart.

Who checks what:

| Where | What it holds to these files |
|---|---|
| OpenPairings (`test/pairings_engine_web/contracts/hall_link_contract_test.exs`) | the files themselves (index, every example against its schema), and the Manubrium pairing link and code it makes |
| Nunki, Polis (vendored in `priv/contracts/vendor/openpairings/hall-link-v1/`) | the frames and join requests the device sends, the frames and answers it takes, the pairing links it reads; and, in the plugin's tests, every answer and frame the server half sends |
| Manubrium (vendored in `contracts/vendor/openpairings/hall-link-v1/`) | the pairing links it reads: its own, and the hall programs' it hands on |

Each consumer runs `contracts:check` (`mix contracts.check`, `npm run
contracts:check`) on every pull request and once a day, so a change here
that a consumer has not caught up with is red there the next morning at
the latest.

## The files

JSON Schema draft-07. Shared shapes are in `common.schema.json`; each other
schema is one message, named by who sends it:

| Schema | Sent by | Over |
|---|---|---|
| `join-request` | Nunki, Polis | `POST <pairing link>` |
| `join-response`, `join-error` | server | the answer to it |
| `device-hello`, `device-leave`, `device-ping` | Nunki, Polis | the line |
| `device-status-nunki`, `device-settings-nunki` | Nunki | the line |
| `device-status-polis`, `device-settings-polis` | Polis | the line |
| `server-welcome`, `server-refused`, `server-round`, `server-leave`, `server-pong` | server | the line, to both |
| `server-settings-nunki`, `server-countdown`, `server-countdown-cancel`, `server-read`, `server-stop` | server | the line, to Nunki |
| `server-settings-polis`, `server-print` | server | the line, to Polis |
| `pairing-link` | nobody: a link as shown, with what it means | the screen, the clipboard, a QR code |

`examples/<schema>.json` and `examples/<schema>.<variant>.json` belong to
`<schema>.schema.json`; every schema has at least one. `index.json` lists
every file but this one. Objects allow keys they do not name: a peer
ignores what it does not know, which is how the protocol grew rooms and
categories while staying version 1.

## Pairing a device

One flow for every hall app.

- **The code.** 32 random bytes, base64url without padding: 43 characters
  (`common.schema.json#/definitions/new_code`). Good once, for **15
  minutes**, bound to one tournament (Nunki, Polis) or one account
  (Manubrium). The server stores its SHA-256 and nothing else; the code
  exists only on the screen it was shown on. Nobody types it, so it need
  not be short.
- **The link.** The code always travels inside a link, and the link is
  the one thing shown: as text with a copy button, and as a QR code that
  encodes exactly that text. What you paste is what you scan.
  - Manubrium: `manubrium://connect?secret=<code>&server=<base url>` (the
    account page, Connect Manubrium). A custom scheme, so a phone's camera
    hands it to the app and never to a browser that would keep the code
    in its history.
  - Nunki and Polis: `https://<server>/p/<app>/join/<code>` (the
    tournament's Settings, Hall announcer or Print station). The device
    POSTs `join-request` to exactly that address. Anything before `/p/` is
    the server's (a sub-path, a port); the last `/p/` counts.
- **Taking it.** Every app takes its link both ways - pasted into its page
  or scanned - and refuses another app's link before anything is sent, so
  the code is not spent on the wrong device, saying in words which app it
  is for. Nunki and Polis run on hall PCs that have no camera to speak of:
  their QR code is scanned by Manubrium on the arbiter's phone, which
  recognises it, says it is for Nunki or Polis on the hall PC, and offers
  to copy or share it there. A phone's own camera app opens the https
  link in a browser, which only GETs it; only a POST spends a code.
- **Readers are lenient.** A reader takes any non-empty base64url run as
  the code. Codes made before this unification (Nunki and Polis: 16 base32
  characters, matched case-insensitively) stay valid until they run out,
  which is fifteen minutes after they were made.

Already-paired devices are untouched by any of this: a joined Nunki or
Polis holds a key (32 bytes, base64url) and a connected Manubrium a device
token, neither of which is a pairing code, and neither changed.

## The line

After a 200 from the join, the device opens one WebSocket per tournament
to `socket` (same host and port as the link; ws for http, wss for https)
and always dials out. JSON text frames, each an object with a `type`.

1. The device says `device-hello` first, with the key in the frame, never
   in the URL. The server answers `server-welcome`, then the device's
   `server-settings-*`, then the latest published round (`server-round`),
   if there is one; Nunki also gets a running `server-countdown`. Or it
   answers `server-refused` and closes.
2. The device sends its `device-status-*` after `welcome` and whenever it
   changes, never twice the same.
3. `device-settings-*` asks the server to change the device's name, room
   or share; the server keeps the truth and answers with its own
   `server-settings-*` (with `error` when it turned the request down).
   The device shows what the server says, not what it asked for.
4. A round goes out when its `rev` differs from the last one sent and it
   is not older than that one. A round taken back is never sent.
5. Keeping it up: a WebSocket ping every 25 seconds from the device; a
   line silent for 75 seconds is dead to the device, 90 to the server. A
   lost line is tried again after 1 second, doubling to 30; after a
   refusal, 60.
6. Either side may say `leave`: the device was removed there.

The app-specific parts - what Polis prints when, how Nunki reads a round
aloud, the board-share rules - are in each app's `docs/protocol.md`.

## Changing it

Additive changes (a new optional key, a new frame type a peer may ignore)
stay version 1: change the schema and its examples here, then
`contracts:sync` in each consumer, then their tests. Anything a version-1
peer would misread is version 2, a new directory, and a new `v` on the
wire.
