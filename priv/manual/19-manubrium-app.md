# The Manubrium app

Manubrium is a phone app for running a tournament from the playing hall. Its
home screen is the current round: tap a board, tap the result. It keeps
working when the hall's signal does not, and sends what you entered once it
can. The organiser and editors can also pair the next round, change the
pairings by hand, publish, look at the standings, change players and the
settings an arbiter touches mid-event. An arbiter on the tournament enters
results, logs incidents (with a photo if you like) and confirms or rejects
what Manubrium Lite phones entered.

One app can hold several servers - pairings.cloud, a club's own server, the
desktop copy on the hall's laptop - and switch between them.

> [!NOTE] Manubrium or Manubrium Lite?
> Manubrium Lite is the result page a phone opens from a Phone QR code
> ([Results](07-results.md)), in the browser, with no account and nothing to
> install. The app is for the people who run the tournament: it needs an
> account on the server and does more than results.

> [!WARNING] A first build
> The server side is built and tested. The app itself has not yet been
> through the App Store or Google Play; until it has, it is installed by hand
> from its own build.

## Connecting the app {#connecting}

1. On the server, open your account page (your name, top right, then
   **Account**) and go to **Manubrium app**.
2. Click **Connect a phone**. A QR code appears, with the same thing as a
   link under it.
3. In the app, tap **Add a server** and scan the code. If the camera cannot
   be used, copy the link and paste it in instead.
4. The phone appears in the list on the account page, with its name and the
   last four characters of its token.

The code works once, for fifteen minutes, and is shown only that one time. If it
runs out, click **Connect a phone** again. Each phone gets a code of its
own: two phones cannot share one.

The app also scans the join codes of the hall programs, Nunki
and Polis, which run on a PC without a camera. It does not
join them itself: it says which program the link is for and offers to copy or
share it, so you can get it to that PC and paste it there. Every pairing code,
the app's own and the hall programs', works once, for fifteen minutes.

A connected phone can do what your account can do, in the tournaments you
work in, and nothing more. If someone takes you off a tournament, the phone
loses it at the same moment.

## On a desktop copy {#desktop}

The desktop version has no accounts and listens only on the computer itself,
which a phone cannot reach. So connecting takes one step more:

1. In any tournament, open **Phone QR** and switch on **Let phones on this
   network connect**. Pick the computer's address on the hall's network.
2. Then make the code on the account page as above. The code points the app
   at that address, not at the computer's own one.

The phone has to be on the same network (the hall's Wi-Fi). Without the
switch, the account page refuses to make a code and says why.

## What the app can do {#what-it-does}

| | Organiser, editor | Arbiter |
| --- | --- | --- |
| See the round, enter and clear results | yes | yes |
| Confirm or reject a result from a Manubrium Lite phone | yes | yes |
| Log incidents, with a photo | yes | yes |
| Look at incident photos, add one to a logged incident | yes | no |
| Pair the next round, undo the latest round | yes | no |
| Change the pairings by hand, finish hand edits | yes | no |
| Publish a round (pairings, results, standings) | yes | no |
| Standings, with the tournament's tie-breaks | yes | no |
| Late entries, withdraw and re-enter, rounds off, basic player fields | yes | no |
| Add players from the FIDE list (and the Belgian list where it is on) | yes | no |
| Check players in, requested byes | yes | no |
| Mid-event settings | change | no |
| Start a new tournament | yes, as its owner | yes, as its owner |
| Share the results-site link | yes | yes |
| Codes for hall boxes (live boards) | yes | no |
| The hall's printer and announcer: see them, reprint, countdown, announce | yes | no |

Results entered without a signal wait on the phone and go when it can. If
somebody else changed the same board in the meantime, the app does not
overwrite it: it shows what the board says now and leaves the decision to
you. Everything else - pairing, hand edits, publishing, players, settings -
needs a connection, and the app says so.

Some questions are answered at the desk, never from a phone: the
pairing-number question, leaving FIDE mode, bye exclusions, pairing while a
round's hand edits are still open, a round robin's schedule, and team
events. The app says which one and leaves the round unpaired.

## A new tournament {#new-tournament}

The app can start a tournament of your own: name, dates, place and venue,
pairing system, number of rounds, time control, federation and whether it
is FIDE-rated. It is made exactly as **New tournament** on the server makes
it, from your own defaults for new tournaments (**Account**, **New
tournaments**), and every round is dated to the first day, with the last
round on the end date if that is a different day. Refine the dates on the
**Dates** page later. Team tournaments are started on the server.

## Players, check-in and byes {#players}

**Adding from a list.** Search the FIDE list by name or FIDE ID; with the
Belgian player lookup switched on (**Features**) and the Belgian list
downloaded, the Belgian list can be searched as well. Type at least three
characters. Picking a player fills them in exactly as picking them in the
Players page's add form would, rating from the tournament's main list
included. Someone already in the tournament is marked as such and cannot be
added twice.

**Check-in.** A player's *present* switch is the Players page's **Pr.**
column: a player who is not present is marked absent for the whole event and
not paired until you switch them back.

**Requested byes.** The rounds a player asked to sit out are listed with
their kind: where the tournament asks the bye type, a half-point,
zero-point or full-point bye, otherwise simply *absent*. The app can change
them for the rounds not yet paired, with the same questions the player
dialog asks (a second half-point bye, a round already sent for rating). A
round that is already paired is changed on the round itself.

## Sharing and hall boxes {#sharing}

A tournament on the results site has its OpenResults link in the app, to
share however you like. With live boards in the hall, each board in the
round shows what the box saw (playing or finished, the number of moves, the
board's result) and marks it when that differs from the entered result. The
box never enters a result; you do. The organiser and editors can list the
boxes' codes, make a new one - with a name of your choosing, which the list
then shows; the full code is shown once, to scan or type into the box - and
withdraw one, as on the **Boards** settings page.

## The hall's printer and announcer {#hall}

If the hall has a print station (Polis) or an announcer (Nunki) joined to the
tournament, **More** has a **Hall (print stations and announcers)** card for
the organiser and editors. It lists them with their room and whether
they are online, and has three things to press:

- **Reprint round**: the latest published round's pairings, place cards, both,
  the standings, a player list in alphabetical order with board and room, or
  result slips, one per board. Every print station that is online prints it.
  The standings are sent just before they are printed, so they are the
  standings of that moment, and a tournament that may not print them yet (the
  last round of a FIDE-mode event with a postponed game still open) prints
  nothing and says why.
- **Countdown to the round**, to the start of the latest round, from 1 to 30 minutes, and
  **Cancel countdown** for the one that runs. The announcers say it at ten, five and one
  minute and at zero.
- **Announce**: one of five ready-made announcements (silence, switch off
  phones, take your seats, hand in your results, come to the arbiter) or a
  line of your own, up to 300 characters. The announcer says it aloud and
  shows it on the hall screen.

The app says how many devices a command reached. If it reached none, nothing
was online to receive it, and the app says so rather than pretending: check
the device on the station's page. A station is added in OpenPairings, in the
tournament's Settings, and an account without the print station or the
announcer switched on has no Hall card to press. Needs a connection; nothing
here waits on the phone.

## Changing the pairings by hand {#hand-edits}

The same hand edits as on the Pairings page ([Pairing a round](06-pairing.md)),
from the round screen:

- **Swap two players.** Tap a board, **Change the pairing**, **Swap with
  another player**, and pick the other one: on another board, on the same
  board (a colour swap), or someone not on a board at all (a substitution).
- **A player is not playing.** **Not playing this round** empties the seat.
  Where the tournament asks the bye type, pick it; otherwise the player is
  absent.
- **An empty seat.** Tap the board: give the remaining player the bye, fill
  the seat from the players not on a board, or swap them elsewhere.
- **Not on a board.** Under the boards, tick two players to pair them on a
  new board, or one to give the bye. An empty last board can be removed.
- **Finish hand edits** checks the round, as at the desk. If the pairing
  checker would pair it differently, the app shows its boards and keeps
  yours only when you say so; the difference is recorded with the round.

When the desk would ask something first - the round is not the latest, it
was already sent for rating, the new boards break a pairing rule, a second
half-point bye - the app asks the same question with the same sentences,
and changes nothing until you answer. Team events are changed at the desk.

## Results from Manubrium Lite phones {#lite-results}

A result entered on a Manubrium Lite phone shows on its board with
**Phone**, and a line above the boards counts how many wait for a look. Tap
the board: it says which phone entered what. **Confirm** keeps it and marks
it checked; **Reject** clears the board, and the audit trail says which
phone's result you turned down. If the board changed in the meantime, the
app says what it shows now and does nothing. Results you, or another arbiter
with the app, enter are your own and need no confirming.

## Incident photos {#photos}

When you log an incident, **Take a photo** adds one: the camera on the
phone, shrunk before it is sent. It waits with the incident if there is no
signal. The organiser and editors can add a photo to an incident logged
earlier (**More**, **Incidents**, **Add photo**) and look at one
(**Photo**). An incident has at most one photo; only JPEGs of a sane size
are taken. Photos are never public, and an arbiter's phone can send one but
not open anyone's.

On the desk, **Incidents** has **Mark handled** for each incident: it stays on the list but
loses its highlight, and can be opened again. **Remove** deletes an incident with its
note and photo after a confirmation; the audit trail keeps a line saying it existed.

## Settings from the phone {#settings}

**More**, **Settings**, **Change the mid-event settings**: the time
control, the chief and deputy arbiter, the venue and city, the number of
rounds, what the pairing bye scores, whether the bye type is asked, shared
places and the tie-breaks. Anything the tournament has locked by now - in
FIDE mode the rounds, the bye's value and the tie-breaks once round 1 is
paired - is shown greyed out, and the server refuses it with the same
sentence as the Settings page. Everything else in the settings stays at the
desk.

## Signing a phone out {#signing-out}

On the account page, under **Manubrium app**, click **Sign out** beside the
phone. It is refused from its next request on; results it had not sent yet
stay on the phone, unsent. The app can also sign itself out. Do this for a
phone that is lost, sold or handed to somebody else.
