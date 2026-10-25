# Teamtoernooien

Een teamtoernooi is een toernooi met als format **Zwitsers (teams)** of **Rondetoernooi
(teams)**: vink **Teamtoernooi** aan wanneer je het aanmaakt. Teams spelen wedstrijden; een
wedstrijd is een reeks individuele partijen, bord tegen bord. De individuele partijen
zijn overal elders gewone partijen (resultaten, spelerskaarten, het FIDE-ratingrapport), en
de teamlaag is erop gebouwd.

Keizer kan geen teamtoernooi zijn.

## Opzetten {#setting-up}

1. Maak het toernooi aan met *Teamtoernooi* aangevinkt.
2. **Teams** (een tabblad naast Spelers, alleen getoond bij teamtoernooien): voeg elk team toe met een
   naam, een optionele korte naam voor smalle kolommen (die staat bij de tiebreakberekening en
   wordt niet gepubliceerd) en een optionele captain, een optionele **reeks** en een optionele **club**. Een team kan worden verwijderd zolang het in geen
   enkele ronde zit; een team dat in een gepaarde wedstrijd zit, wordt in plaats daarvan teruggetrokken.
3. Registreer de spelers zoals gewoonlijk op de pagina Spelers. Het toevoegformulier en het
   registratievenster hebben een keuzelijst **Team** (*Geen team* of een van de teams), zodat een
   speler meteen op een team komt, onderaan de opstelling; je kunt ze ook later vanaf de kaart van
   het team op een team zetten. De lijst met spelers heeft een kolom **Team** (team en bord,
   sorteerbaar, standaard aan bij een teamtoernooi), en de afgedrukte spelerslijst ook.
   **De volgorde van een opstelling is de bordvolgorde**:
   bord 1 eerst. De pijltjes verplaatsen een speler naar een hoger of lager bord; *Verwijderen*
   haalt hem van het team af. Spelers boven de wedstrijdgrootte worden gemarkeerd als *reserve*.
4. **Borden per wedstrijd** (op de pagina Teams; standaard 4) wordt vastgelegd wanneer ronde 1
   gepaard wordt.
5. **De volgorde van de teams.** De volgorde van de kaarten wordt de paringnummers van de teams
   wanneer ronde 1 gepaard wordt. Verplaats teams met de pijltjes of druk op **Rangschikken op rating**.
   Teams die je niet zelf verplaatst heeft, worden gerangschikt op rating wanneer ronde 1 gepaard wordt.
   Hoe de rating van een team berekend wordt, is de optie *Teamrating voor de volgorde van de teams* op de pagina Opties (geavanceerd):
   de standaard (olympiaderegel) is het gemiddelde van de hoogst gerate spelers, één per bord; de
   alternatieven zijn het gemiddelde van de eerste borden in bordvolgorde, het
   gemiddelde van de hele opstelling, of een rating die je per team intypt. De rating van een team
   kan ook op zijn kaart ingetypt worden, en die wint dan. Een ongerate speler telt mee met de rating
   ingesteld bij *Rating van een ongerate speler* (standaard 1400).

   **Volgorde loten** zet de teams in een willekeurige volgorde, voor een competitie waarvan het
   reglement de teamnummers laat loten (C.04.6 art. 1.1.2 laat de methode aan het reglement over).
   De knop staat er alleen wanneer de teamrating *Per team ingetypt* is: met elke andere methode
   horen de nummers de ratings te volgen, en *Rangschikken op rating* of een hernummering na ronde 1
   zou de loting ongedaan maken. Een volgorde die je zelf hebt ingesteld (of een eerdere loting)
   wordt pas na een bevestiging vervangen, en er wordt eerst een herstelpunt bewaard. De pagina
   Teams vermeldt wanneer er geloot is en het auditspoor noemt de volgorde; verplaats je daarna een
   team of rangschik je op rating, dan verdwijnt die vermelding, want de volgorde is dan niet meer
   de loting. Kan tot ronde 1 gepaard is; de loting haalt het toernooi niet uit de FIDE-modus.
6. **Matchpunten** (Instellingen, Puntentelling): standaard 2, 1, 0. Een competitie die 3, 1, 0
   scoort, past ze hier aan. Partijpunten tellen de bordresultaten. In de FIDE-modus kun je ze
   niet meer wijzigen zodra ronde 1 gepaard is: het reglement van de competitie legt de
   puntentelling vooraf vast (C.04.6 art. 1.2.1).

   *Gerangschikt en gepaard op*, in dezelfde kaart, is de **primaire score**: **Matchpunten eerst**
   (de FIDE-standaard, C.04.6 art. 1.2.2) of **Partijpunten (bordpunten) eerst**, voor competities
   die bordpunten boven matchpunten rangschikken. Het teamklassement wordt er eerst op gesorteerd,
   de afdrukken en OpenResults volgen, en een teams-Zwitsers wordt gepaard in scoregroepen van die
   score; de andere score beslist de kleuren tussen teams met dezelfde score. *Terugzetten naar de
   FIDE-standaard* bij de tiebreaks begint dan met de andere score (GP, MP, DE, BB, SB). Artikel
   1.2.1 laat het reglement kiezen, dus beide waarden houden het toernooi in de FIDE-modus; net als
   de punten kun je ze daar niet meer wijzigen zodra ronde 1 gepaard is.
7. **Tiebreaks** (Instellingen, Tiebreaks): een teamtoernooi krijgt de teamtiebreaks aangeboden. De
   FIDE-standaard is MP, GP, DE, BB, SB.

Elke actie op de pagina Teams is een gewone knop met een gesproken naam, en het
resultaat wordt aangekondigd.

### Opstellingen {#line-ups}

Opties, *Opstellingen*: **Verplicht** (de standaard en de FIDE-procedure): een team speelt met de
spelers van zijn opstelling in bordvolgorde, een reserve schuift op voor een afwezige speler, en een
bord dat een team niet kan bezetten is een forfaitoverwinning voor de tegenstander.

Opties, *Bordvolgorde*: **Vast volgens de spelerslijst** (de standaard en de FIDE-procedure): een
speler die lager op de lijst staat zit nooit boven een speler die hoger staat, dus een opstelling kan
spelers weglaten maar niet herordenen. **Voor elke ronde gekozen**: elke speler van de spelerslijst,
reserves inbegrepen, mag aan elk bord van een opstelling zitten, handig voor competities waarin de
captain elke ronde de volgorde bepaalt. De koppeling zet een team nog steeds in lijstvolgorde; je
past de volgorde aan op de pagina *Opstellingen* van de wedstrijd, voordat het eerste resultaat van de
wedstrijd is ingevoerd. Het TRF26-rapport heeft niets extra's nodig: de regel van elke speler noemt de
tegenstander en kleur die echt gespeeld zijn, dus de opstellingen zoals gespeeld staan erin. In
FIDE-modus kan deze instelling niet meer wijzigen zodra ronde 1 is gekoppeld.

> [!NOTE] Optioneel: teams paren zonder spelers
> Sommige competities en schoolevenementen registreren alleen wedstrijdscores. De wedstrijden worden
> gepaard zonder spelers, en een wedstrijd kan gegeven worden als een *Wedstrijdscore* (bijvoorbeeld 2½-1½ op vier
> borden) die het programma op de borden schrijft. Een wedstrijd met lege plaatsen is geen
> gerate partij en wordt aan FIDE gerapporteerd met een waarschuwing op de pagina Exporteren.

> [!FIDE]
> In FIDE-modus liggen de opstellingen en bordvolgordes vast na ronde 1; een nieuwe speler kan
> nog wel onderaan een team als reserve worden toegevoegd.

## Paren {#pairing}

**Rondetoernooi (teams).** *Het hele toernooi paren* paart elke ronde in één keer vanuit de
Berger-tabel. Het team dat eerst genoemd wordt, heeft Wit op bord 1 en op elk oneven bord
en Zwart op de even borden; de kleur van een team in de wedstrijd is de kleur
van zijn bord 1.

**Zwitsers (teams).** Het programma paart elke ronde team tegen team volgens de regels van
FIDE C.04.6 (februari 2026).

> [!FIDE] C.04.6 (februari 2026)
> Matchpunten
> zijn de primaire score (partijpunten, als het reglement van de competitie dat zegt - pagina
> Puntentelling), de andere score beslist de kleuren, de eerste kleur wordt bij loting
> getrokken. De door de paring toegekende bye scoort een gelijkspel in de wedstrijd (wedstrijd- en partijpunten
> worden op de pagina Puntentelling ingesteld).

Een teams-Zwitsers dat al speler voor speler gepaard was in een eerdere versie, gaat op die manier verder.

Elke paring is een **wedstrijd**. De pagina Paringen toont boven de borden een tabel *Wedstrijden - ronde N*:
wedstrijdnummer, aantal borden, de teams, de partijpuntenscore tot nu toe, de wedstrijdpunten zodra elk bord
een resultaat heeft, een link naar de opstellingen van de wedstrijd (*Opstellingen*) en de bediening
**Forfait bij beslissing**.

- *Opstellingen*: de pagina van een wedstrijd bepaalt wie op welk bord speelt; een opstelling
  behoudt de bordvolgorde van het team (tenzij de bordvolgorde voor elke ronde wordt gekozen); ze kan alleen gewijzigd worden voordat het eerste resultaat
  van de wedstrijd is ingevoerd.
- *Forfait bij beslissing*: *Aan team A* / *Aan team B* maakt elk bord van de wedstrijd het
  forfaitresultaat van dat team, en *Geen van beide* registreert een dubbel forfait (beide verliezen). *Beslissing intrekken* herstelt de oude
  resultaten. Eerst wordt een herstelpunt bewaard. De borden van een beslechte wedstrijd tonen het
  resultaat van de beslissing en krijgen geen eigen resultaat: trek eerst de beslissing in.
- Een dubbel forfait dat de paring zelf schreef (beide teams afwezig in de ronde, of geen van
  beide kan een speler opstellen) heeft geen oude resultaten om te herstellen. *Beslissing
  intrekken* stelt de wedstrijd dan opnieuw op, zoals de paring dat nu zou doen - markeer dus eerst
  het team of zijn spelers als beschikbaar. Zolang niemand opgesteld kan worden, wordt het
  geweigerd.
- Een bord dat met de hand is toegevoegd (twee spelers uit de lijst van niet-spelenden) sluit aan bij de
  wedstrijd van hun teams wanneer het tafelnummer, de kleuren en de bordvolgordes passen; past het niet,
  dan wordt het gemarkeerd als **geen team** en telt het voor geen enkel team totdat je het een bord van
  de wedstrijd maakt.

**Een wedstrijd die als geheel forfait is.** Instellingen - Puntentelling - *Een wedstrijd die als geheel
forfait is* bepaalt hoeveel partijpunten zo'n wedstrijd oplevert voor het team dat ze krijgt toegewezen:
*Eén per opgesteld bord* (de standaard: een team dat zeven van de acht borden bezette, wint met 7-0, en een
team zonder opstelling met 0-0 - de wedstrijdpunten kloppen in beide gevallen) of *Het volledige aantal
borden* (8-0 op acht borden, wat er ook was opgesteld, voor reglementen die het resultaat van een teamforfait
vastleggen). Het geldt voor een wedstrijd die bij beslissing forfait werd verklaard voordat er een partij
van gespeeld was, en voor een wedstrijd tegen een team dat als team niet aan de ronde deelneemt. Een
wedstrijd die forfait werd verklaard nadat er partijen gespeeld waren, behoudt de som van haar borden, en
één forfaitbord blijft altijd het punt van één bord. De extra partijpunten zijn van het team: geen enkel
bordresultaat verandert en de bordstatistieken van de spelers blijven wat ze waren. De instelling gaat mee
in de export van het toernooi; een TRF heeft er geen record voor, dus een toernooi dat uit een TRF wordt
ingelezen, staat weer op de standaard.

> [!FIDE] Een wedstrijd die als geheel forfait is
> Puntentelling: in FIDE-modus kan dit na ronde 1 niet meer gewijzigd worden. De standaard is C.07 art.
> 11.1.2 zoals het er staat (partijpunten zijn de som van de punten van de spelers); het volledige aantal is
> het eigen reglement van de competitie.

Een team kan op zijn kaart voor een ronde als **afwezig als team** gemarkeerd worden (vóór de ronde gepaard
is); een team dat zich terugtrekt, wordt in de rangschikking getoond als *teruggetrokken, resultaten niet
geteld* (rondetoernooi, minder dan 50% gespeeld, FIDE Algemeen Reglement 6.6). Trekken twee teams
die nog tegen elkaar moesten spelen zich allebei terug, dan is hun wedstrijd een dubbel forfait,
welk team zich ook eerst terugtrok; zet je een van beide terug, dan krijgt die de forfaitwinst
terug.

## Resultaten en rangschikking {#results-and-standings}

Resultaten worden per bord ingevoerd op de pagina Paringen, zoals in elk toernooi
([Resultaten](07-results.md)). De teamrangschikking (pagina Stand) toont de
rangschikking, het team, gespeelde wedstrijden, gewonnen-gelijk-verloren, wedstrijdpunten en de
teamtiebreaks, elk met zijn berekening (voor elke ronde de tegenstander en wat die waard was, een forfait,
een bye). De pagina toont ook **bordstatistieken**: per boordnummer de spelers die daar zaten, met
partijen, punten, percentage en prestatie.

### Reeks en club {#series-and-club}

Een team kan een **reeks**-label dragen ("Reeks 1", "Reeks 2": vrije korte tekst) en een **club**, beide
op de kaart van het team. Een reeks is alleen een label: teams van alle reeksen worden samen gepaard,
als één Zwitsers toernooi. Zodra een team er een heeft, krijgen de teamrangschikking (pagina en
afdruk) een kolom *Reeks*. De club wordt bewaard en getoond op de kaart.

### Teams uit elkaar houden {#keeping-teams-apart}

Instellingen, **Verboden paringen** heeft regels voor teams, zoals voor spelers: *Teams van
dezelfde club* (de club op de kaart van elk team, vergeleken zonder hoofdletters of spaties aan
de rand; een team zonder club wordt nooit gegroepeerd) en *Teams die ik kies* (een groep die
elkaar niet mag ontmoeten). Elke regel is een **regel** of een **wens (indien mogelijk)**, voor
elke ronde of een reeks rondes.

De regel op club ziet alleen een club die ingevuld is. Met een regel *Teams van dezelfde club*
zegt de pagina Verboden paringen hoeveel teams geen club hebben, zodat de regel er niet voor geldt,
en zet ze naast elk team een veld voor de club. Komen de meeste spelers van een team (minstens twee
met een club, drie kwart van hen) uit dezelfde club, dan wordt die club als knop voorgesteld, hier en op het
bewerkformulier van het team; ze wordt alleen ingevuld als je op de knop drukt. De formulieren op de pagina
Teams zeggen dat de club voor die regel nodig is, maar ze blijft optioneel. Voor spelers heeft een regel
*Zelfde club* dezelfde melding voor spelers zonder club, met een link naar de lijst met spelers,
gefilterd op hen.

Een regel wordt absoluut aan de paring doorgegeven: voor de procedure van C.04.6 is een
verboden paar een paar dat al tegen elkaar speelde, dus verder verandert er niets. Een wens
beslist alleen tussen paringen die de procedure gelijk rangschikt, na [C10], en kost nooit een
kleur, een floater of de bye. Geen van beide is C.04.6, en de documenten zeggen dat.

Laten de regels een ronde zonder paring terwijl ze er zonder wel zou zijn, dan wordt de ronde
niet gepaard en zegt de knop welke groepen gelden en welke ervan, alleen opgeheven, de ronde
toch laat doorgaan.

> [!FIDE] FIDE-modus
> Teamregels worden behandeld zoals die van spelers. Regels die vóór ronde 1 zijn ingesteld,
> halen het toernooi niet uit de FIDE-modus (C.05 5.2). Een wens die een match echt verplaatst,
> of een regel die na ronde 1 wordt toegevoegd, gewijzigd of verwijderd, stelt eerst de twee
> vragen van *FIDE-modus verlaten?* en wordt voor het rapport genoteerd.

Het TRF-dialect van de engine schrijft ze als `XXO team-forbidden 3 11 16 @1-2` en
`XXO team-soft-pairs ...` (teamnummers, rondes optioneel), zodat een paringscontrole het bestand
ermee naspeelt; een TRF met die records importeert ze terug als regels voor de genoemde teams.
Een teamtoernooi schrijft nooit `XXP` of `260`, die spelers noemen. Het TRF26-rapport zelf bevat
geen teamrecords.

### De volgorde van de teams corrigeren {#correcting-the-order-of-the-teams}

Tot ronde 4 gepaard is, kunnen de teamnummers van een Zwitsers teamtoernooi nog gecorrigeerd
worden, zoals de nummers van spelers ([Spelers en ratings](04-players-and-ratings.md), C.04.2
2.3). Op de pagina Teams opent **Teamnummers…** de lijst:

- **Wisselen** ruilt de nummers van twee teams met dezelfde teamrating (de rating die de optie
  *Teamrating voor de volgorde van de teams* uitrekent, of die op de kaart getypt is);
- **Opnieuw aanmaken uit ratings** hernummert elk team op die rating, met behoud van de volgorde
  van teams met gelijke rating. Veranderen er twee of meer nummers, dan toont een bevestiging
  eerst wiens nummer verandert.

Rondes die al gepaard zijn, gebruikten de oude nummers, dus een paringscontrole zal ze niet
meer reproduceren. Elke wijziging komt in het auditspoor en geen van beide haalt het toernooi uit
de FIDE-modus. Tot ronde 4 waarschuwt de pagina Paringen boven de knop om te paren wanneer de nummers
de teamratings niet meer volgen, en opent *Opnieuw aanmaken uit ratings…* de lijst. Vanaf ronde 5
verandert er niets meer. Een team-rondetoernooi is uitgesloten: zijn schema is over de nummers
getekend.

Die ronde is *Teamnummers kunnen gecorrigeerd worden tot ronde* op de pagina Opties (geavanceerd,
kaart Teams; standaard 4). Een vroegere ronde vergrendelt ze alleen sneller. Een latere is niet de
regel van C.04.2 - C.04.6 art. 1.1.3 laat de hoofdarbiter ruimte, maar een instelling die er de
regel voor het hele toernooi van maakt, is toch een afwijking - dus bij het bewaren krijg je eerst
de twee vragen van *FIDE-modus verlaten?*, en Instellingen - FIDE noemt ze zoals elke andere
afwijking. Een team toevoegen in een latere ronde staat daar los van: een laat team krijgt altijd
een nummer na de andere.

### Gemiddelde rating opgesteld {#average-rating-fielded}

De gemiddelde rating van de spelers die een team echt opstelde (spelers zonder rating tellen niet
mee in het gemiddelde) staat bij elke match op de pagina Paringen (*Gem. Elo*, beide kanten),
op de matchbladen en de afgedrukte teamparingen, en in de teamrangschikking als de waarde van
de laatste match van het team. Het is alleen ter informatie: de volgorde van de teams en de
paring lezen het niet.

### Individuele rangschikking {#individual-ranking}

Op de pagina Stand van een teamtoernooi toont *Individuele rangschikking* elke speler die gespeeld
heeft: plaats, naam, rating, team, reeks, partijen, punten en percentage. Als er reeksen zijn, houdt het
filter *Reeks* één reeks over. De afdruk (*Individuele rangschikking* op de pagina Afdrukken, of
*Afdrukken* onder de tabel) volgt het filter.

De volgorde is **punten, dan percentage, dan rating** (hoogste eerst), dan naam; spelers met gelijke
punten en percentage delen een plaats en de rating bepaalt alleen hun volgorde. De punten zijn die van
de bordstatistieken, een forfaitwinst inbegrepen; *Partijen* telt alleen echt gespeelde partijen, en
een speler die er geen gespeeld heeft, staat er niet in.

### Teamtiebreaks {#team-tie-breaks}

MP (wedstrijdpunten), GP (partijpunten), DE (directe ontmoeting), BB (bordpunten gewogen per bord), SB, BH:GP, EMGSB, EGMSB, EGGSB, EDE (uitgebreide directe ontmoeting), TBR (resultaten op het topbord), BBE (eliminatie op het laagste bord), SSSC. De rest van de tabel
"Mandatory Tie-Breaks" van FIDE wordt ook aangeboden, met de vormen `/P` en `/K<n>`;
[Rangschikking en tiebreaks](08-standings-and-tiebreaks.md) legt de toevoegingen uit.
De behandeling van niet-gespeelde partijen van C.07 artikel 16 geldt voor byes, forfaitwedstrijden
en teruggetrokken teams in een teams-Zwitsers.

- **Gewonnen, gelijk, verloren** en de tiebreaks lezen een wedstrijd af aan zijn wedstrijdpunten:
  een wedstrijd toegekend aan een team dat niemand opstelde, staat 0-0 op de borden en is toch
  een (forfait)winst.
- **DE** telt een wedstrijd die zonder partij beslist werd - een forfait of een dubbel forfait -
  alleen in een rondetoernooi mee, waar C.07 art. 15.2 forfaits tot partijen maakt; in een
  teams-Zwitsers is het geen ontmoeting (art. 6.1.1). Het getoonde getal en de volgorde komen
  overeen.
- **BB** telt een bye in een teams-Zwitsers als een winst op elk bord, zoals Board Count dat doet
  (C.07 art. 12), al zijn de partijpunten die van een gelijkgespeelde wedstrijd.

## Afdrukken {#printing}

De pagina Afdrukken somt **teamparingen**, **teamrangschikkingen**, **teamkruistabel**,
**wedstrijdformulieren**, **teamopstellingen**, **bordprijzen** en de **individuele rangschikking** op
([Afdrukken](09-printing.md)). De pagina Stand heeft dezelfde als knoppen:
*Kruistabel*, *Wedstrijdformulieren*, *Opstellingen*, *Bordprijzen*; de individuele rangschikking heeft daar een eigen weergave.

**Matchresultaatbladen** zijn één A4-pagina per match van een ronde: beide opstellingen met bord,
kleur, speler, rating en FIDE-ID, een vak voor elk resultaat, de gemiddelde rating die elk team
opstelde, de matchscore en handtekeningregels voor beide captains en de arbiter.
**Opstellingsformulieren (blanco)** zijn de andere helft van het papier: één pagina per team voor
een ronde, door de captains in te vullen vóór de ronde. Is de ronde gepaard, dan noemt een
formulier al het team, de tegenstander en de kleur van elk bord; daarvoor blijft de tegenstander
leeg. Er staat een regel voor elk bord, regels voor reserves en een handtekening van de captain.
Beide gelden voor één ronde (`?round=n`), en één team of match kan apart afgedrukt worden.

## Rapporteren en publiceren {#reporting-and-publishing}

Het TRF26-rapport bevat de teams en hun bordvolgordes (records 310 en
013, 362, 320 voor de bye en 330 voor een forfaitwedstrijd), en een teambestand kan
opnieuw geïmporteerd worden. De `192` van een teams-Zwitsers noemt de primaire score -
`FIDE_TEAM_TYPEA_MP_GP`, of `FIDE_TEAM_TYPEA_GP_MP` met partijpunten eerst - en een import leest
die terug. De Bergercode van een team-rondetoernooi heeft er geen plaats voor, dus een
team-rondetoernooi uit een TRF komt terug op matchpunten. Teambestanden worden geïmporteerd waarbij de wedstrijden worden herbouwd waar de borden dat
eenduidig aangeven. Teamtoernooien worden gepubliceerd op OpenResults net als andere
([Publiceren](14-publishing.md)).

> [!NOTE]
> Teamevenementen hebben uitgebreidere regels voor forfaits, opstellingen en terugtrekkingen
> dan hier vermeld. Als het programma iets weigert, zegt de melding waarom.
