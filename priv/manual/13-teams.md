# Team tournaments

A team tournament is one whose format is **Swiss (teams)** or **Round robin
(teams)**: tick **Team tournament** when you create it. Teams play matches; a
match is a set of individual games, board against board. The individual games
are ordinary games everywhere else (results, player cards, the FIDE rating
report), and the team layer is built on them.

Keizer cannot be a team tournament.

## Setting up

1. Create the tournament with *Team tournament* ticked.
2. **Teams** (a tab next to Players, shown for team tournaments only): add each
   team with a name, an optional short name for narrow columns (it labels the
   tie-break working and is not published), an optional captain, an optional
   **series** and an optional **club**. A team can
   be deleted while it is in no round; a team that is in a paired match is
   withdrawn instead.
3. Register the players on the Players page as usual. The add form and the
   registration dialog have a **Team** select (*No team* or one of the teams),
   so a player goes straight onto a team, at the bottom of its line-up; or put
   each one on a team later from the team's card. The Players list has a
   **Team** column (team and board, sortable, on by default in a team event),
   and so does the printed player list. **The order of a roster is the board order**:
   board 1 first. The arrows move a player to a higher or lower board; *Remove*
   takes them off the team. Players beyond the match size are marked *reserve*.
4. **Boards per match** (on the Teams page; default 4) is fixed when round 1
   is paired.
5. **The order of the teams.** The order of the cards becomes the teams'
   pairing numbers when round 1 is paired. Move teams with the arrows or press
   **Order by rating**. Teams you did not move by hand are ordered by rating when
   round 1 is paired. How a team's rating is worked out is the Options page's
   *Team rating for the order of the teams* (advanced): the default (Olympiad rule)
   is the average of the highest-rated players, one for each board; the
   alternatives are the average of the first boards in board order, the
   average of the whole roster, or a rating typed for each team. A team's
   rating can also be typed on its card, which then wins. An unrated player
   counts as the rating set in *Rating of an unrated player* (1400 by default).

   **Draw the order by lot** puts the teams in a random order, for a
   competition whose rules draw the team numbers (C.04.6 Art. 1.1.2 leaves the
   method to them). It is offered only when the team rating is *Typed in for
   each team*: with any other method the numbers are meant to follow the
   ratings, and *Order by rating* or a regeneration after round 1 would undo
   the draw. An order you set yourself (or an earlier draw) is replaced only
   after a confirmation, and a restore point is saved first. The Teams page
   says when the order was drawn and the audit trail lists it; moving a team
   or ordering by rating afterwards removes the note, since the order is no
   longer the draw. Possible until round 1 is paired; the draw does not leave
   FIDE mode.
6. **Match points** (Settings, Scoring): 2, 1, 0 by default. A league that scores
   3, 1, 0 changes them here. Game points count board results. In FIDE mode
   they cannot change once round 1 is paired: the competition's rules state the
   scoring in advance (C.04.6 Art. 1.2.1).

   *Ranked and paired by*, in the same card, is the **primary score**: **Match
   points first** (the FIDE default, C.04.6 Art. 1.2.2) or **Game points
   (board points) first**, for leagues that rank board points above match
   points. The team standings are sorted by it first, the printouts and
   OpenResults follow, and a team Swiss is paired in score groups of it; the
   other score decides colours between teams on the same score. *Reset to
   FIDE default* on the tie-breaks then starts with the other score (GP, MP,
   DE, BB, SB). Article 1.2.1 lets the competition's rules choose, so either
   value keeps the tournament in FIDE mode; like the points, it cannot change
   once round 1 is paired there.
7. **Tie-breaks** (Settings, Tie-breaks): a team tournament is offered the team
   tie-breaks. The FIDE default is MP, GP, DE, BB, SB.

Every action on the Teams page is an ordinary button with a spoken name, and the
result is announced.

### Line-ups

Options, *Line-ups*: **Required** (the default and the FIDE procedure): a team
plays with the players of its roster in board order, a reserve moves up for an
absent player, and a board that a team cannot fill is a forfeit win for the
opponent.

Options, *Board order*: **Fixed by the roster** (the default and the FIDE
procedure): a player listed lower on the roster never sits above one listed
higher, so a line-up can leave players out but not reorder them. **Chosen for
each round**: any player of the roster, reserves included, may sit on any board
of a line-up, which suits leagues that let the captain set the order each
round. The pairing still seats a team in roster order; you change the order on
the match's *Line-ups* page, before the first result of the match is entered.
The TRF26 report needs nothing extra: each player's line names the opponent
and colour actually played, so the line-ups as played are what it carries. In
FIDE mode this setting cannot change once round 1 is paired.

> [!NOTE] Optional: pair teams without players
> Some leagues and school
> events only record match scores. The matches are paired without players, and
> a match can be given as a *Match score* (for example 2½-1½ on four boards)
> that the program writes onto the boards. A match with empty seats is not a
> rated game and is reported to FIDE with a warning on the Export page.

> [!FIDE]
> In FIDE mode the rosters and board orders are fixed after round 1; a new
> player can still be added at the bottom of a team as a reserve.

## Pairing

**Round robin (teams).** *Pair the whole tournament* pairs every round at once from the
Berger table. The team named first has White on board 1 and on every odd board
and Black on the even boards; the colour of a team in the match is the colour
of its board 1.

**Swiss (teams).** The program pairs each round team against team by the rules
of FIDE C.04.6 (February 2026).

> [!FIDE] C.04.6 (February 2026)
> Match points
> are the primary score (game points, when the competition's rules say so -
> Scoring page), the other score decides colours, the first colour is drawn
> by lot. The pairing-allocated bye scores a drawn match (match and game points
> are set on the Scoring page).

A team Swiss that was already paired player by player in an earlier version continues
that way.

Each pairing is a **match**. The Pairings page shows a table *Matches - round N*
above the boards: match number, number of boards, the teams, the game-point
score so far, the match points once every board has a result, a link to the match's
line-ups (*Line-ups*) and the **Forfeit by decision** controls.

- *Line-ups*: the page of a match sets who plays on which board; a line-up
  keeps the team's board order (unless the Board order is chosen for each round); it can be changed only before the first result
  of the match is entered.
- *Forfeit by decision*: *To Team A* / *To Team B* makes every board of the
  match the forfeit result of that team, and *Neither team* records a double
  forfeit (both lose). *Withdraw the decision* gives back the old results. A
  restore point is saved first. The boards of a decided match show the
  decision's result and take no result of their own: withdraw the decision
  first.
- A double forfeit the pairing wrote itself (both teams out of the round, or
  neither able to field a player) has no old results to give back.
  *Withdraw the decision* then seats the match again, as the pairing would
  seat it now - so mark the team or its players available first. While
  nobody could be seated it is refused.
- A board added by hand (two players from the not-playing list) joins its
  teams' match when the table number, the colours and the board orders fit; when it does
  not, it is marked **no team** and counts for no team until you make it a board
  of the match.

**A match forfeited as a whole.** Settings - Scoring - *A match forfeited as a
whole* says what such a match pays the team it is awarded to in game points:
*One per board it seated* (the default: a team that seated seven of eight
wins 7-0, and a team with no line-up 0-0 - the match points are right either
way) or *The full board count* (8-0 on eight boards whatever was seated, for
regulations that fix the score of a team forfeit). It applies to a match
forfeited by decision before any game of it was played, and to a match
against a team out of the round as a team. A match forfeited after games
were played keeps the sum of its boards, and a single forfeited board is
always one board's point. The extra game points belong to the team: no
board's result changes and no player's board statistics move. The setting
travels with the tournament's export; a TRF has no record for it, so a
tournament read from a TRF comes back on the default.

> [!FIDE] A match forfeited as a whole
> Scoring: in FIDE mode it cannot be changed after round 1. The default is
> C.07 Art. 11.1.2 as written (game points are the sum of the players'
> points); the full count is the competition's own regulation.

A team can be marked **absent as a team** for a round on its card (before the
round is paired); a team that withdraws is shown as *withdrawn, results not
counted* in the standings (round robin, under 50% played, FIDE General
Regulations 6.6). When two teams that still had to meet both withdraw, their
match is a double forfeit, whichever withdrew first; reinstating one of them
gives it the forfeit win back.

## Results and standings

Results are entered per board on the Pairings page, as in any tournament
([Results](07-results.md)). The team standings (Standings page) show the
rank, the team, matches played, won-drawn-lost, match points and the team
tie-breaks, each with its working (for each round the opponent and what it was
worth, a forfeit, a bye). The page also shows **board statistics**: per board
number, the players who sat there, with games, points, percentage and performance.

### Series and club

A team can carry a **series** label ("Series 1", "Reeks 2": free short text) and
a **club**, both on its card. A series is only a label: teams of every series
are paired together, as one Swiss. When any team has one, the team standings
(page and printout) gain a *Series* column. The club is stored and shown on the
card.

### Keeping teams apart

Settings, **Forbidden pairings** has rules for teams, as it has for
players: *Teams of the same club* (the club on each team's card, compared
without regard to capitals or spaces at the edges; a team with no club is
never grouped) and *Teams I choose* (a group that must not meet). Each is a
**rule** or a **wish (if possible)**, for every round or a window of them.

The club-based rule can only see a club that is filled in. With a *Teams of the
same club* rule in place, the Forbidden pairings page says how many teams have
no club, so the rule does not apply to them, and puts a club box beside each
one. When most of a team's players (at least two with a club, three quarters of
them) are from one club, that club is offered as a button, here and on the team's
edit form; it is only filled in when you press it. The Teams page's forms say
the club is needed for that rule, but it stays optional. For players, a *Same
club* rule has the same notice for players without a club, with a link to the
Players list filtered to them.

A rule is handed to the pairing as absolute: to the C.04.6 procedure a
forbidden pair is a pair that has already met, so nothing else moves. A wish
only decides between pairings the procedure ranks equal, after [C10], and
never costs a colour, a floater or the bye. Neither is C.04.6, and the
documents say so.

If the rules leave a round with no pairing where it would pair without
them, the round is not paired and *Pair round N* says which groups are in
force and which of them, lifted on its own, would let the round through.

> [!FIDE] FIDE mode
> Team rules are treated as the players' are. Rules set before round 1 do not
> leave FIDE mode (C.05 5.2). A wish that actually moves a match, or any rule
> added, changed or removed once round 1 is paired, asks the two *Leave FIDE
> mode?* questions first and is recorded for the report.

The engine's TRF dialect writes them as `XXO team-forbidden 3 11 16 @1-2`
and `XXO team-soft-pairs ...` (team numbers, rounds optional), so a pairing
checker replays the file with them; a TRF with these records imports them
back as rules for the named teams. A team event never writes `XXP` or `260`,
which name players. The TRF26 report itself carries no team records.

### Correcting the order of the teams

Until round 4 is paired a team Swiss's team numbers can still be corrected,
as players' numbers can ([Players and ratings](04-players-and-ratings.md),
C.04.2 2.3). On the Teams page, **Team numbers…** opens the list:

- **Exchange** swaps the numbers of two teams with the same team rating (the
  rating the *Team rating for the order of the teams* option works out, or
  the one typed on the card);
- **Regenerate from ratings** renumbers every team by that rating, keeping the
  order of teams of equal rating. If two or more numbers change, a
  confirmation lists whose first.

Rounds already paired used the old numbers, so a pairing checker will no
longer reproduce them. Each change is written to the audit trail, and neither
takes the tournament out of FIDE mode. Until round 4 the Pairings page warns
above *Pair round N* when the numbers no longer follow the team ratings, and
*Regenerate from ratings…* opens the list. From round 5 nothing renumbers. A
team round robin is excluded: its table was drawn over the numbers.

The round is the Options page's *Team numbers can be corrected until round*
(advanced, Teams card; 4 by default). An earlier round only locks them
sooner. A later one is not C.04.2's rule - C.04.6 Art. 1.1.3 leaves the Chief
Arbiter room, but a setting that makes it the rule for the whole event is
still a departure - so saving it asks the two *Leave FIDE mode?* questions
first and lists it on Settings - FIDE like any other departure. Adding a team
in a later round has nothing to do with this: a late team is always
numbered after the others.

### Average rating fielded

The average rating of the players a team actually fielded (unrated players
are left out of the mean) is shown for each match on the Pairings page
(*Avg. Elo*, both sides), on the match sheets and the printed team pairings,
and in the team standings as the value of the team's latest match. It is for
information only: the order of the teams and the pairing do not read it.

### Individual ranking

On the Standings page of a team tournament, *Individual ranking* shows every
player who played: rank, name, rating, team, series, games, points and
percentage. With series in use, a *Series* filter keeps one series. The printout
(*Individual ranking* on the Print page, or *Print* under the table) follows the
filter.

The order is **points, then percentage, then rating** (higher first), then name;
players level on points and percentage share a rank and the rating only orders
them. Points are the ones the board statistics add up, a forfeit win included;
*Games* counts only games actually played, and a player who has played none is
not listed.

### Team tie-breaks

MP (match points), GP (game points), DE (direct encounter), BB (board points
weighted by board), SB, BH:GP, EMGSB, EGMSB, EGGSB, EDE (extended direct
encounter), TBR (top board results), BBE (bottom board elimination), SSSC. The rest
of FIDE's Mandatory Tie-Breaks table is offered too, `/P` and `/K<n>` forms
included; [Standings and tie-breaks](08-standings-and-tiebreaks.md) lists the suffixes.
The unplayed-game handling of C.07 Article 16 applies to byes, forfeited
matches and withdrawn teams in a team Swiss.

- **Won, drawn, lost** and the tie-breaks read a match by its match points:
  a match awarded to a team that seated nobody is 0-0 on the boards and
  still a (forfeit) win.
- **DE** counts a match decided without a game - forfeited, or a double
  forfeit - only in a round robin, where C.07 Art. 15.2 makes forfeits games;
  in a team Swiss it is no encounter (Art. 6.1.1). The number shown and the
  order agree.
- **BB** counts a team Swiss bye as a win on every board, as Board Count
  does (C.07 Art. 12), although its game points are a drawn match's.

## Printing

The Print page lists **team pairings**, **team standings**, **team cross table**,
**match result sheets**, **team rosters**, **board prizes** and the **individual ranking**
([Printing](09-printing.md)). The Standings page has the same as buttons:
*Cross table*, *Match sheets*, *Rosters*, *Board prizes*; the individual ranking has its own view there.

**Match result sheets** are one A4 page per match of a round: both line-ups
with board, colour, player, rating and FIDE ID, a box for each result, the
average rating each team fielded, the match score, and signature lines for
both captains and the arbiter. **Line-up forms (blank)** are the other half
of the paper: one page per team for a round, for the captains to fill in
before the round. Once the round is paired a form already names the team, its
opponent and the colour of each board; before that the opponent is left
blank. It has a row for each board, rows for reserves and a captain's
signature. Both are for one round (`?round=n`), and a single team or match can
be printed on its own.

## Reporting and publishing

The TRF26 report carries the teams and their board orders (records 310 and
013, 362, 320 for the bye and 330 for a forfeited match), and a team file can
be imported again. A team Swiss's `192` names its primary score -
`FIDE_TEAM_TYPEA_MP_GP`, or `FIDE_TEAM_TYPEA_GP_MP` with game points first -
and an import reads it back. A team round robin's Berger code has no place
for it, so a team round robin read from a TRF comes back on match points.
Team files are imported with the matches rebuilt where the boards say it
unambiguously. Team tournaments are published to OpenResults like others
([Publishing](14-publishing.md)).

> [!NOTE]
> Team events have more detailed rules for forfeits, line-ups and withdrawals
> than are listed here. When the program refuses something, its message says why.
