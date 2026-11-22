# Map Editor Improvements

**Szerzők**: Monsterfish, Heroesflorian
**Verzió**: 1.0.65

Több információt jelenít meg a szerkesztett térképről a térképszerkesztőben, és hiányzó eszközökkel bővíti azt: fák növekedési fokozatai, almafák, több bokor, kidöntött fák, kavics és vas, sziklavariánsok, csordaméretek és sok más. Minden rész külön kikapcsolható a beállításokban.

## Térképszámlálók

A tájszerkesztőben:

- **Tippek a kategóriagombokon.** Mutass egy gombra a térkép darabszámaiért és a játék korlátaiért:
  - **Állatok:** állatok és egységek a tényleges korláthoz képest (2499, Extreme-ben 9999), csordák és csoportok — minden elhelyezett csorda és csapatcsoport egy helyet foglal a saját 1249-es korlátból — valamint madarak: varjak (jelölők fákon, külön korlát nélkül) és sirályok (legfeljebb 99).
  - **Növényzet:** fák és bokrok. Minden növény közös, 1999-es korláton osztozik.
  - **Sziklák:** sziklák.
- **Állatok menü:** a szarvas, teve, nyúl és oroszlán gombok mind mutatják a térképen lévő darabszámukat.
- **Növényzet menü:** minden fa- és bokorgombon látható az adott növény darabszáma.

A kulcs gomb felett piros **„i”** gomb ül. Kattints rá az elrejtéshez, majd újra a megjelenítéshez. A beállítások döntik el, hogy láthatóan induljon-e. A gombok leíró sora kissé jobbra tolódik, hogy elférjen.

## Fák és bokrok

A Növényzet menü fái aszerint rendeződnek, milyen talajon terjednek: elöl a három termékeny talajon terjedő (oázisfű, sűrű és ritka bozót) vékony zöld kerettel, utána a terméketlen talajon terjedő (föld, köves föld, dűnék) vékony bézs kerettel.

- **Növekedési fokozat az ecsetméretből.** Fa kiválasztásakor az ecsetméret szabja meg a fa nagyságát:

  | Ecset | Fa |
  |---|---|
  | 1–3 | fiatal fák, a legkisebbel kezdve |
  | 4 | kifejlett (amit a szerkesztő mindig lerakott) |
  | 5 | kifejlett; a favágók békén hagyják, amíg vissza nem alakul rendes fává |
  | 6 | elszáradt fa |
  | 7 | elszáradt fa, amely hamarabb eltűnik |

  A bokrok mindig egyformák.
- **Almafa gomb** a Növényzet menüben (a leíró sorban „Apple tree”, németül „Apfelbaum”).
- **Több bokor.** Az ötszínű bokor kiválasztásakor a Növényzet menü feletti sor mind az öt színt felkínálja.
- **Kidöntött fák.** Fa kiválasztásakor a felette lévő sor állva, majd kidöntve mutatja a fát minden lehetséges rönkszámmal (9-től 1-ig kifejlett fánál, kevesebbel kisebbeknél, nulla elszáradtaknál; a legkisebbek 1 rönkkel dőlnek ki). Kattints egyre kidöntött fák lerakásához; ismételt kattintás, az álló fa vagy a menübeli fa visszaállítja az álló fákat.
- **Véletlen keverékek.** A Növényzet menü feletti sorok „?” gombokat kapnak:
  - **Véletlen fa** (első a kidöntöttek sorában): minden lerakott fa véletlen növekedési fokozatot kap a legkisebbtől az ecsetéig (1-es ecsetnél és elszáradt fáknál nincs).
  - **Véletlen kidöntött fa** (utolsó a kidöntöttek sorában): kidöntött fák 1-től a fa maximumáig terjedő véletlen rönkszámmal.
  - **Véletlen bokor** (utolsó a bokrok sorában): az öt bokorszín véletlen keveréke.

  Kattints újra vagy válassz másik gombot a leállításhoz.
- **Fák akadályok mellett.** Jelölőnégyzet a felső sor végén. Bepipálva fák közvetlenül épületek, sziklák, falak és más fák mellé is helyezhetők (bokrok amúgy is állhatnak ott). Mutass rá az állapotához.
- **Rendezettebb sorok.** Felül a fák (almafával és jelölőnégyzettel), az onnan áthelyezett bokor pedig az alsó, rendezett bokorsorba kerül.
- **Fa-előnézet.** Az egér alatti mezőn kirajzolja a lehelyezendő fát a megfelelő fokozatban vagy kidöntve — a pipettánál is. Kicsinyítve vagy tiltott helyen nem látszik; elrejtett menünél (Tab) is megjelenik.
- **Nincs bokorhalmozás.** Már foglalt mezőre nem rakható új növény. Korábban egyes bokrok láthatatlanul halmozódtak a fakapacitást fogyasztva; a radír mostantól minden egymásra rakott bokrot eltávolít.

A Növényzet menü feletti sor a térkép fölött lebeg; a rá való kattintás nem rak le semmit a térképre.

## Talajtextúrák

A Textúrák menü felső sorának végére **Kavics**, az alsó végére **Vas** kerül (ugyanaz a vas, mint a Magasságok menüben). Mindkét sor egyenletesen oszlik el.

Ha a Textúrák menüben már van vas, a Magasságok menü vas gombja eltávolítható (beállítás).

**Maszk.** Gomb (félig kitöltött négyzet) a tájszerkesztő menüjének bal felső sarkában. Bekapcsolva a természeti eszközök (magasságok, textúrák, víz, növényzet, sziklák és pipetta) csak az először kattintott mezővel azonos textúrájú mezőket módosítják. Az egér elengedése után a következő kattintás új céltextúrát választ.

## Víz

A Víz menü visszakap két folyódíszt az első Stronghold szerkesztőjéből, amelyet a Crusader ma is támogat, csak gombok nélkül:

- **Hab:** fehér tajték és permet, mint vízesés alatt, az ecset alatti minden folyómezőre. Tengerre is helyezhető, amely ekkor habos folyóvá válik (beállítás).
- **Kis hullámok:** az egér alatti egyetlen folyómezőre.

Mindkettő csak folyóra tehető és a térképpel együtt mentődik (lásd `docs/river-decorations.md` a modul tárhelyében).

## Sziklák

- **Útjelző tábla csetepaté térképeken.** A csetepaté térképek ugyanazt a Sziklák menüt kapják, mint a küldetéstérképek.
- **Véletlen forgatás az előnézetben.** Másodpercenként egyszer fordul minden képkocka helyett, így az előnézet pontosan a lerakandó sziklát mutatja.
- **Variánssor.** A Sziklák menü felett mutatja a választott méret négy variánsát a lehelyezési tájolásban. Kattintásra rögzül egy variáns; újabb kattintásra vagy bármely Sziklák gombra visszaáll a váltakozás.
- **Láthatatlan sziklák.** Jelölőnégyzet a Sziklák menü jobb oldalán. Bepipálva minden lerakott szikla azonnal láthatatlan („2k kő trükk”) 4000 szikla lerakása nélkül is: a mezők blokkoltak, de nem rajzolódik ki szikla. A pipa kivételével ismét rendes sziklák kerülnek le. Normálisan mentődnek a térképbe.
- **Láthatatlan sziklák radírozása.** A tájradír a láthatatlan sziklákat is eltávolítja, bokortrükk nélkül.
- **Extra kis szikla.** Ötödik variáns a legkisebb szikláknál, amely a játékban megvan, de a szerkesztő sosem rakta le; rendesen mentődik.
- **Elveszett sziklák eltávolítása.** Jobb alsó gomb a Sziklák menüben, amely törli a listából az emelés/süllyesztés által megtört, majd bokrokkal teljesen elfedett, mező nélküli sziklákat; tippje mutatja a számukat.

## Magasságok

- **Maximális magasság.** Az első Stronghold eszköze visszatér a Minimális magasság mellé: 156-ra emeli az ecset alatti talajt.
- **Magasságeszköz-beállítások.** Panel a Magasságok menü felett (alulról felfelé):
  - **Talajtextúrák visszaállítása** (kezdetben ki): visszaadja-e a talaj egyszerű kinézetét (a fennsíkoknál földet). Kikapcsolva csak a magasság változik.
  - **Sziklamezők törése** (kezdetben ki): megtörje-e a sziklákat az emelés, süllyesztés, kiegyenlítés, domb és hegy. Kikapcsolva a sziklák épek maradnak.
  - **Víz mellőzése** és **Termőföld mellőzése** (kezdetben ki): érintetlenül hagyja a vizet/várárkot, illetve a bozótos/oázisfüves mezőket.
  - Emeléshez, süllyesztéshez és kiegyenlítéshez: **Tartományhoz igazítás** (kezdetben be), **Megfordítás** (csak kiegyenlítés: érdesíti a talajt és sík földön véletlen buckákat képez; a Ctrl nyomva tartása ugyanezt teszi, beállítható), **magasságtartomány** (kétvégű csúszka, kezdetben 8–156, 0–255 között) és **erősség** (lépésenkénti változás; 7 a játék kiegyenlítési üteme).
  - **Sziklamagasság változása** (lista, kezdetben Egész szikla): *Csak mező*, *Egész szikla* vagy *Szikla törlése* (mint Minimális magasság).
  A tartomány, igazítás, megfordítás és mellőzések kilépéskor visszaállnak. Az emelés és süllyesztés nem fordul át többé a szélső értékeken.

## Vármód

A térképszerkesztő vármódjának építési menüjében:

- **Épületszámlálók** a minitérkép felett:
  - a térkép összes épülete a korláthoz képest (vártornyokkal, tájépületekkel és épületrészekkel együtt);
  - az összes játékos épületei együtt;
  - az aktuális játékos épületei.

  Játékosépület minden épület, amelyet ellenség lerombolhat.
- **Toronyromok.** A Tornyok menü felett mind az öt torony romja elérhető.
- **Alagútbejárat és ostromsátrak.** A katonai menüben alagútbejárat az alagútásók céhénél, hat ostromsátor a mérnökök céhénél.
- **Szobor és szentélyek.** A fel nem használt 2×2-es szobor, 2×2-es szentély és 1×1-es szentély a variánsok végén vagy (kikapcsolt variánsoknál) a jó dolgok menüje felett.
- **Épületvariánsok.** Kert (2×2, 3×3, 4×4), szobor, szentély, pöcegödör és kunyhó minden variánsa a menü feletti sorban rögzíthető a másodpercenkénti váltás helyett.
- **Több vártorony.** Új vártorony nem törli a korábbit (sem a tábortüzét); a legújabb az aktív, a többi megmarad.
- **Több raktár- és toborzóépület.** Kaszárnyák, zsoldostáborok, céhek és hasonló egyedi épületek nem törlődnek, a további raktárak, magtárak és fegyvertárak bárhová lerakhatók és korlátlanul maradhatnak üresen (korábban játékosonként 8 üres magtár/fegyvertár és 32 üres raktár).
- **Torony-kővetőgépek és balliszták bárhová.** Bármely egységmentes mezőre (talaj, fal, kapu, bármely torony, vártorony). Saját szögletes és kerek tornyokon a megszokott módon működnek.
- **Vártorony tábortűz vagy raktár nélkül.** **Csak vártorony** és **Raktár nélkül** változatok hozzá igazított előnézettel és helyellenőrzéssel.
- **Sérült falak.** **Sérült** változat lépcsőkhöz, alacsony falhoz, magas falhoz és pártázathoz, megőrzött magassággal.
- **Romos katedrális.** **Romos** változat („Kerak” küldetés grafikája); játékban teljesen működő katedrális marad, és a pipetta is romosként veszi fel. Az eredeti `gm/tile_churches.gm1` kell hozzá.
- **Kiásott, tervezett és állandó várárok.** **Kiásott**, **Tervezett** és **Állandó** (játékban nem temethető be és nem törölhető) módok a kapuházak menüje felett.
- **Várárok mocsárra.** A mocsár alatta marad és betemetéskor visszatér.
- **Az árok eltávolítása megőrzi a talajt.** Csak várárkos mezőket módosít, visszaadva a magasságot és megőrizve a textúrát.
- **Épületnevek balrább.** 100 pixellel balra tolva, hogy ne takarják a számlálókat.
- **Korlát.** Törölhető 1×1-es korlát a Romok menü jobb alsó szabad helyén.

## Csordák

Szarvas, oroszlán, nyúl vagy teve kiválasztásakor az Állatok menü feletti panel mutatja a csorda méretét (fix + véletlen rész) és csoportos viselkedését. A jelölőnégyzettel az ecsethez igazodik: 2 × ecsetméret − 1 állat (1-es ecsetnél egyes állatok, 7-esnél 13 fős csordák).

Piros kuka gombok az Állatok menüben: a varjútól jobbra **Összes varjú törlése** (fák maradnak), a sirálytól jobbra **Összes sirály törlése**, jobb oldalon **Összes állat törlése** (mint Alt + E; madarak maradnak).

Ha kevesebb mint 200 csorda és csoport hozható létre, a képernyő tetején figyelmeztető sor mutatja a maradékot.

## Radír

A radír a radírozott mezők feletti sirályokat is eltávolítja. A menü feletti panel szabja meg a célpontját:

- **Mind** – minden, mint korábban.
- **Állatok** – állatok, varjak (fák maradnak) és sirályok.
- **Egységek** – minden más egység.
- **Épületek** – épületek, vártornyok, romok és falak.
- **Növényzet** – fák és bokrok.
- **Sziklák** – sziklák, a láthatatlanok is.

## Térképbeállítások

- **Zárolt térképek mutatása:** jelölőnégyzet a szerkesztő Betöltés ablakában a zárolt térképek megjelenítéséhez.
- **Térképbeállítások gomb** a térkép menüképernyőjén (Mentés és Kilépés mellett), a Kiegyensúlyozott / Kiegyensúlyozatlan vagy Invázió / Gazdasági gomboktól jobbra. Az Alt + , menüt nyitja.
- **Nagyobb Térképbeállítások menü:** cím; Egyjátékos és Többjátékos; egyjátékos alatt Ostrom, Invázió, Gazdasági és Szabad építés; többjátékos alatt 160, 200, 300, 400, Egyéni és 10–400 méretcsúszka (elengedéskor lép életbe); Kiegyensúlyozott és Domb királya; Térkép zárolása; Vissza (Esc és Alt + , is zárja). Mindez benne maradt a játék kódjában, csak a gombok hiányoztak. A Térkép zárolása a „Küldetés” zárat állítja be, ami megtartja a térképet a csetepaté listában, de elrejti a szerkesztő Betöltés ablakában, amíg a „Zárolt térképek mutatása” nincs bepipálva.

## Képek

Az almafa és a kavics gomb a modul `images` mappájának képeit használja: `apple.png`, `apple_hover.png`, `apple_selected.png` és `gravel.png`, `gravel_hover.png`, `gravel_selected.png` (normál, egér felette, kiválasztott). Saját képekre cserélhetők.

## Ecsetek

A játék ecsetei kétszer számolják az egér alatti mezőt, és kihagyják a bal felső sarkot az előnézetben és lerakáskor is. Ezzel a beállítással minden ecset teljes alakú.

## Visszavonás és újra

Két nyílgomb a térképszerkesztő bal felső sarkában (táj- és vármenüben): a bal visszavonja az utolsó módosítást (épületek, fák, sziklák, állatok, textúrák, víz, magasságok), a jobb visszaállítja. Akár 20 lépést megőriz. Minden kattintás és minden lenyomva tartott ecsetvonás egy-egy lépés; hatástalan kattintások nem rögzülnek. Visszavonás utáni új művelet törli az újra végrehajtható lépéseket; másik térkép betöltése új előzményt indít.

## Pipetta

Pipetta gomb a tájszerkesztő bal oszlopában, az ecsetméret felett. Kiválasztásakor megjelenik a **Magasságok**, **Textúrák**, **Objektumok**, **Mind** sor és a tartalomsáv.

- **Felvétel:** kattints egy mezőre (a pipetta egyetlen mezőt mutat).
- **Átadás:** kattints vagy húzd végig a magasságok, textúrák vagy mindkettő átviteléhez. A Magasságok békén hagyja a textúrát, a Textúrák a magasságot.
- **Objektumok:** kattints épületre, falra, fára vagy sziklára. Az épületek és falak a saját gombjukhoz hasonlóan, eredeti tulajdonosuknak kerülnek le (címere kiválasztódik); a fák (azonos fajta, fokozat vagy rönkszám) és sziklák (azonos fajta és forgatás) saját eszközeik módján, húzással, előnézettel és ellenőrzésekkel. Kilépéskor az ecset, forgatás és kidöntött választás visszaáll. A fák fokozata követi a növekedési beállítást.
- **Mind** egy fát vagy 1×1-es sziklát is felvesz, és az ecset alatti minden szabad mezőre leteszi.
- Magasság nem kerül tengerre, partra, mocsárra, várárokra, sziklákra, falakra és épületekre; textúra nem kerül sziklákra, falakra és épületekre. A szirtkövek meredek széleken tisztulnak és újraképződnek. Az **Alt** lenyomva tartása minden mezőre átviszi a magasságot és textúrát (sziklák maradnak; kísérleti).
- A pipetta vagy módjának újraválasztása kiüríti. A **P** kiválasztja és továbblépteti a módokat. A **Ctrl** lenyomva tartásával új mező vehető fel; elengedve ismét fest. Mindhárom billentyű módosítható vagy kikapcsolható.
- A visszavonás a pipettát is kezeli.

## A menü mindig maradjon friss

A játék csak akkor rajzolja újra a szerkesztőmenüt, ha az egér felette van. Ha a térkép fölött történik változás (gyorsbillentyű, számlálók), a menü elavult marad, míg vissza nem viszed rá az egeret. Ezzel a beállítással folyamatosan frissül a térképszerkesztőben, a játékon kívül semmin nem változtat.

## Nyersanyagrács

Korábban a Monsterfish által készített különálló Resource Grid Overlay modul.

A térképre rajzolja azt a rácsot, amelyet az MI használ, amikor helyet keres kőfejtői,
vasbányái, olajkútjai és favágói számára: 5 × 5 mezős blokkokat. Egyetlen blokkon belül lévő
kőlelőhely többet ér az MI számára, mint ugyanez a lelőhely négy blokkra szétosztva. Kirajzolja
azt a négy vonalat is, ahol az MI várelrendezése a vártorony helyzete alapján elfordul, valamint
minden blokkban azokat a mezőket, amelyeket egy MI-vasbánya elfoglalna.

- **Alt + G** megjeleníti vagy elrejti a térképszerkesztőben. A beállításokban másik Alt +
  billentyű kombináció is választható. Olyan Custom Hotkeys verzióval, amely engedi a
  moduloknak saját gyorsbillentyűk hozzáadását, a gyorsbillentyű ott szerepel a Map Editor
  Improvements alatt és módosítható; a játékokhoz tartozó második gyorsbillentyű is megjelenik,
  kezdetben billentyű nélkül.
- Alapértelmezés szerint csak sík nézetben (Szóköz) látható, ahol a vonalak pontosan a talajra
  esnek, a V nézetben pedig rejtve marad.
- **Rács engedélyezése játék közben** segítségével egy próbajátékban is ellenőrizheted a
  vonalakat.
- A rács, a határok és a vasbánya alaprajzának színe módosítható.
- A térkép elhagyása elrejti, így a szerkesztő minden megnyitásakor rejtve indul.
- Semmi nem mentődik a térképbe.

A régi Resource Grid Overlay modulban megadott beállítások nem kerülnek átvételre. Ha
módosítottad őket, állítsd be újra ennek a modulnak a „Nyersanyagrács” csoportjában. Ha a
Resource Grid Overlay még be van kapcsolva, ez a modul átengedi neki a rácsot; kapcsold ki.

## Jó tudni

- Működik Stronghold Crusader és Stronghold Crusader Extreme alatt is; a korlátokat a játékból olvassa ki, így az Extreme a saját magasabb egységkorlátját mutatja.
- A fák, bokrok és sziklák a játék listáiban elfoglalt helyek alapján számolódnak; az egymásra halmozott bokroknál minden példány számít.
- Semmi extra adat nem mentődik a térképbe.
