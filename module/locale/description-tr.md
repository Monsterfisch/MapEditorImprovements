# Map Editor Improvements

**Yazarlar**: Monsterfish, Heroesflorian
**Sürüm**: 1.0.65

Harita düzenleyicinin üzerinde çalıştığınız harita hakkında daha fazla bilgi göstermesini sağlar ve düzenleyicide eksik olan araçları ekler: ağaç büyüme aşamaları, elma ağaçları, daha fazla çalı, devrilmiş ağaçlar, çakıl ve demir, kaya çeşitleri, sürü boyutları ve daha fazlası. Her bölüm ayarlardan ayrı ayrı kapatılabilir.

## Harita sayaçları

Arazi düzenleyicide:

- **Kategori düğmelerinde ipuçları.** Bir düğmenin üzerine geldiğinizde haritadaki mevcut sayı ile oyun sınırı gösterilir:
  - **Hayvanlar:** gerçek sınıra (2499, Extreme'de 9999) karşı hayvanlar ve birimler, kendi sınırına (1249) sahip sürüler ve gruplar — koyduğunuz her sürü ve birlik grubu bir yer tutar — ve kuşlar: kargalar (ağaç işaretleri, ayrı sınırı yok) ve martılar (en fazla 99).
  - **Bitki Örtüsü:** ağaçlar ve çalılar. Tüm bitkiler ortak 1999 sınırını paylaşır.
  - **Kayalar:** kayalar.
- **Hayvanlar menüsü:** geyik, deve, tavşan ve aslan düğmeleri haritada her birinden kaç adet olduğunu gösterir.
- **Bitki Örtüsü menüsü:** her ağaç ve çalı düğmesi o bitkiden haritada kaç tane bulunduğunu gösterir.

Anahtar düğmesinin üstünde kırmızı bir **«i»** düğmesi bulunur. Tümünü gizlemek için tıklayın, geri getirmek için tekrar tıklayın. Başlangıçta gösterilip gösterilmeyeceği ayarlardan seçilir. Düğme açıklama satırı yer açmak için hafifçe sağa kayar.

## Ağaçlar ve çalılar

Bitki Örtüsü menüsündeki ağaçlar yayıldıkları zemine göre sıralanır: önce verimli zeminde yayılan üç ağaç (vaha çimeni, sık ve seyrek çalılık) ince yeşil çerçeveyle, ardından verimsiz zeminde yayılan ağaç (toprak, taşlı toprak, kumullar) ince bej çerçeveyle.

- **Fırça boyutundan büyüme aşaması.** Bir ağaç seçiliyken fırça boyutu yerleştirilen ağacın büyüklüğünü belirler:

  | Fırça | Ağaç |
  |---|---|
  | 1 ila 3 | genç ağaçlar, en küçüğünden başlayarak |
  | 4 | tam büyümüş (düzenleyicinin normalde hep yerleştirdiği) |
  | 5 | tam büyümüş; oduncular tekrar normal ağaca dönene kadar ona dokunmaz |
  | 6 | kurumuş ağaç |
  | 7 | daha çabuk kaybolan kurumuş ağaç |

  Çalılar her zaman aynı kalır.
- **Elma ağacı düğmesi** Bitki Örtüsü menüsünde (açıklama satırında «Apple tree», Almanca «Apfelbaum»).
- **Daha fazla çalı.** Beş renkli çalı seçiliyken Bitki Örtüsü menüsünün üzerindeki satır beş rengin tamamını sunar.
- **Devrilmiş ağaçlar.** Bir ağaç seçiliyken üstteki satır ağacı önce ayakta, ardından tutabileceği her kütük sayısıyla devrilmiş olarak gösterir: tam büyümüş ağaç için 9'dan 1'e, küçüklerde daha az, kurumuşlarda hiç yok (en küçük ağaçlar 1 kütükle bir üst aşama gibi devrilir). Birine tıklayarak devrilmiş ağaç koyabilir; tekrar ona, ayaktaki ağaca veya menüdeki ağaca tıklayarak dik ağaçlara dönebilirsiniz.
- **Rastgele karışımlar.** Bitki Örtüsü menüsünün üzerindeki satırlara «?» düğmeleri eklenir:
  - **Rastgele ağaç** (devrilmiş ağaç satırının ilki): konulan her ağaç en küçükten fırça boyutuna kadar rastgele bir büyüme aşaması alır (fırça 1 ve kurumuş ağaçlarda yoktur).
  - **Rastgele devrilmiş ağaç** (devrilmiş ağaç satırının sonuncusu): 1'den o ağacın azami değerine kadar rastgele kütük sayılı devrilmiş ağaçlar.
  - **Rastgele çalı** (çalı satırının sonuncusu): beş çalı renginin rastgele karışımı.

  Karıştırmayı durdurmak için tekrar tıklayın veya başka bir düğme seçin.
- **Engellerin yanına ağaç.** Üst satırın sonunda onay kutusu. İşaretliyken ağaçlar binaların, kayaların, surların ve diğer ağaçların hemen yanına konulabilir (çalılar zaten konulabilir). Durumu görmek için üzerine gelin.
- **Düzenli satırlar.** Üst satırda ağaçlar (elma ağacı ve onay kutusu dâhil), alt satırda sıralanmış tüm çalılar bulunur.
- **Ağaç önizlemesi.** Fare altındaki karede fırça aşamasında veya seçili kütükle devrilmiş ağacı gösterir — damlalık için de geçerlidir. Uzaklaştırıldığında veya dikilemeyen yerlerde gösterilmez; menü gizliyken (Tab) de görünür.
- **Çalı yığılması yok.** Zaten bitki bulunan kareye yeni bitki yerleştirilemez. Eskiden görünmez biçimde üst üste yığılıp ağaç sınırını tüketen çalılar artık birikmez; silgi de eski yığınların tamamını tek seferde temizler.

Bitki Örtüsü menüsünün üzerindeki satır haritanın üstünde durur; ona tıklamak haritaya bir şey koymaz.

## Zemin dokuları

Dokular menüsü üst satırın sonuna **Çakıl**, alt satırın sonuna **Demir** ekler (Yükseklikler menüsündeki demirle aynı). İki satır panele eşit dağılır.

Dokular menüsünde demir varken Yükseklikler menüsündeki demir düğmesi kaldırılabilir (ayar).

**Maske.** Arazi düzenleyici menüsünün sol üstünde yarısı dolu kare düğme. Açıkken doğa araçları (yükseklikler, dokular, su, bitki örtüsü, kayalar ve damlalık) yalnızca ilk tıklanan kareyle aynı dokudaki kareleri değiştirir; fareyi bıraktığınızda sonraki tıklama yeni hedef dokuyu seçer.

## Su

Su menüsü ilk Stronghold düzenleyicisinden iki nehir süslemesini geri getirir:

- **Köpük:** şelale altındaki gibi beyaz köpük ve serpinti, fırça altındaki her nehir karesinde. Deniz karelerine de uygulanıp köpüklü nehre dönüştürülebilir (ayar).
- **Küçük dalgalar:** fare altındaki tek nehir karesinde.

İkisi de yalnızca nehir karelerine konur ve haritaya kaydedilir (bkz. modül deposundaki `docs/river-decorations.md`).

## Kayalar

- **Çarpışma haritalarında yol tabelası.** Çarpışma haritaları da yol tabelalı Kayalar menüsünü alır.
- **Önizlemede rastgele döndürme.** Her kare yerine saniyede bir kez döner, böylece önizleme tam koyacağınız kayayı gösterir.
- **Çeşit satırı.** Kayalar menüsünün üzerinde seçili boyutun dört çeşidini yerleştirme yönünde gösterir; tıklayarak bir çeşidi kilitleyebilir, tekrar tıklayarak veya menüden başka düğmeye basarak otomatik değişime dönebilirsiniz.
- **Görünmez kayalar.** Kayalar menüsünün sağındaki onay kutusu. İşaretliyken 4000 kaya koymaya gerek kalmadan doğrudan görünmez kaya («2k taş numarası») koyar: kareler bloklanır ama kaya çizilmez. İşareti kaldırınca normal kayalara döner; haritaya normal kaydedilir.
- **Görünmez kayaları silme.** Arazi silgisi görünmez kayaları da kaldırır; artık çalı numarasına gerek yoktur.
- **Ek küçük kaya.** En küçük kayalar için oyunda var olan ama düzenleyicinin koymadığı beşinci çeşit; normal kaydedilir.
- **Kayıp kayaları kaldır.** Sağ alttaki düğme, yükseltme/alçaltmayla kırılıp çalılarla kapandığı için karesiz kalıp 4000 yuvadan yer yiyen kayaları listeden siler; ipucu sayılarını gösterir.

## Yükseklikler

- **Azami Yükseklik.** İlk Stronghold'un aracı Asgari Yükseklik'in sağına döner ve fırça altını 156 yüksekliğine çıkarır.
- **Yükseklik aracı seçenekleri.** Yükseklikler menüsünün üzerindeki panel (alttan üste):
  - **Zemin dokularını sıfırla** (başlangıçta kapalı): zemini düz görünümüne (platoları toprağa) döndürsün mü. Kapalıyken yalnız yükseklik değişir.
  - **Kaya karelerini kır** (başlangıçta kapalı): yükselt, alçalt, eşitle, tepe ve dağ araçları dokunduğu kayaları kırsın mı. Kapalıyken kayalar bütün kalır.
  - **Suyu yok say** ve **Tarım arazisini yok say** (başlangıçta kapalı): su/hendek veya çalılık/vaha çimeni karelerine dokunmaz.
  - Yükselt, alçalt ve eşitle için: **Aralığa oturt** (başlangıçta açık), **Ters çevir** (yalnızca eşitle: zemini engebelendirir, düz zeminde rastgele tümsekler oluşturur; Ctrl basılı tutmak aynı işi yapar, ayarlanabilir), **yükseklik aralığı** (çift uçlu kaydırıcı, başlangıçta 8–156, 0–255 arası) ve **güç** (adım başına etki; eşitlemede 7 oyunun hızıdır).
  - **Kaya yüksekliği değişiklikleri** (liste, başlangıçta Tüm kaya): *Yalnızca kare*, *Tüm kaya* veya *Kayayı sil* (Asgari Yükseklik gibi).
  Aralık, Aralığa oturt, Ters çevir ve yok sayma kutuları düzenleyiciden çıkınca sıfırlanır. Yükseltme ve alçaltma artık en alt ve en üst sınırda başa sarmaz.

## Kale modu

Harita düzenleyicinin kale modu bina menüsünde:

- **Bina sayaçları** mini haritanın üstünde:
  - oyun sınırına karşı haritadaki tüm binalar (iç kaleler, arazi yapıları ve bileşik parçalar dâhil);
  - tüm oyuncuların toplam oyuncu binaları;
  - seçili oyuncunun oyuncu binaları.

  Oyuncu binaları, düşmanın yıkabileceği binalardır.
- **Kule yıkıntıları.** Kuleler menüsünün üstünde beş kulenin yıkıntıları.
- **Tünel girişi ve kuşatma çadırları.** Askerî menüde tünelciler loncasında tünel girişi, mühendisler loncasında altı kuşatma çadırı.
- **Heykel ve tapınaklar.** Kullanılmayan 2×2 heykel, 2×2 tapınak ve 1×1 tapınak, çeşitlerin sonunda veya (bina çeşitleri kapalıysa) iyi şeyler menüsünün üstünde.
- **Bina çeşitleri.** Bahçe (2×2, 3×3, 4×4), heykel, tapınak, lağım çukuru ve kulübe için tüm çeşitler üst satırda sabit seçilebilir.
- **Birden fazla iç kale.** Yeni iç kale eskisini (ve kamp ateşini) silmez; en yenisi etkin iç kale olur, diğerleri bina olarak kalır.
- **Birden fazla depolama ve asker toplama binası.** Kışlalar, paralı asker kampları, loncalar ve diğer tekil binalar silinmez; ek depolar, ambarlar ve cephanelikler her yere konabilir ve sınırsız sayıda boş bırakılabilir (eskiden oyuncu başına 8 boş ambar/cephanelik ve 32 boş depo).
- **Kule mangonelleri ve balistaları her yere.** Birim olmayan her kareye (zemin, sur, kapı, herhangi bir kule, iç kale) konabilir; oyuncunun kendi kare ve yuvarlak kulelerinde eskisi gibi çalışır.
- **Kamp ateşi veya deposuz iç kale.** **Yalnızca iç kale** ve **Deposuz** seçenekleri, uyarlanmış önizleme ve yer kontrolüyle.
- **Hasarlı surlar.** Merdiven, alçak sur, yüksek sur ve mazgal için yükseklik koruyan **Hasarlı** seçeneği.
- **Yıkık katedral.** **Yıkık** seçeneği («Kerak» görevindeki görsel); oyunda tam çalışan katedral olarak kalır ve damlalık da yıkık olarak kopyalar. Orijinal `gm/tile_churches.gm1` gerektirir.
- **Kazılmış, planlı ve kalıcı hendek.** Kapı binaları menüsünün üstünde **Kazılmış**, **Planlı** ve **Kalıcı** (oyunda doldurulamaz veya silinemez).
- **Bataklık üzerine hendek.** Bataklık altta kalır, hendek dolunca geri gelir.
- **Hendek kaldırma zemini korur.** Yalnızca hendekli kareleri değiştirir, yüksekliği geri verir ve dokuyu korur.
- **Bina adları daha solda.** Sayaçlarla çakışmaması için 100 piksel sola kaydırılır.
- **Bariyer.** Yıkıntılar menüsünün sağ alt boşluğunda silinebilen 1×1 bariyer.

## Sürüler

Geyik, aslan, tavşan veya deve seçiliyken Hayvanlar menüsünün üstündeki panel sürü boyutunu (sabit + rastgele) ve grup davranışını gösterir. Onay kutusu boyutu fırçaya bağlar: 2 × fırça boyutu − 1 hayvan (fırça 1 tek hayvan, fırça 7 ise 13'lük sürü).

Hayvanlar menüsünde kırmızı çöp kutusu düğmeleri: karga yanında **Tüm kargaları sil** (ağaçlar kalır), martı yanında **Tüm martıları sil** ve sağda **Tüm hayvanları sil** (Alt + E gibi; kuşlar kalır).

200'den az sürü ve grup hakkı kaldığında ekran üstünde kalan sayıyı bildiren bir uyarı satırı görünür.

## Silgi

Silgi sildiği karelerin üzerindeki martıları da kaldırır. Menü üstündeki panel neyi sileceğini belirler:

- **Tümü** – eskisi gibi her şey.
- **Hayvanlar** – hayvanlar, kargalar (ağaçlar kalır) ve martılar.
- **Birimler** – diğer tüm birimler.
- **Binalar** – binalar, iç kaleler, yıkıntılar ve surlar.
- **Bitki Örtüsü** – ağaçlar ve çalılar.
- **Kayalar** – görünmez kayalar dâhil kayalar.

## Harita ayarları

- **Kilitli haritaları göster:** düzenleyicinin Yükle penceresinde kilitli haritaları da gösteren onay kutusu.
- **Harita Ayarları düğmesi** harita menü ekranında (Kaydet ve Çıkış ile birlikte), Dengeli / Dengesiz veya İstila / Ekonomi düğmelerinin sağında. Alt + , menüsünü açar.
- **Genişletilmiş Harita Ayarları menüsü:** başlık; Tek Oyunculu ve Çok Oyunculu; Tek Oyunculu altında Kuşatma, İstila, Ekonomi ve Serbest İnşa; Çok Oyunculu altında 160, 200, 300, 400, Özel ve 10–400 harita boyutu kaydırıcısı (bırakıldığında uygulanır); Dengeli ve Tepenin Kralı; Haritayı kilitle; Geri (Esc ve Alt + , de kapatır). Bunların tümü oyun kodunda hâlâ mevcuttu, yalnızca düğmeleri kaldırılmıştı. Haritayı kilitle «Görev» kilidini koyar: harita çarpışma listesinde kalır ama «Kilitli haritaları göster» işaretlenmedikçe düzenleyicinin Yükle listesinde gizlenir.

## Görseller

Elma ağacı ve çakıl düğmeleri modülün `images` klasöründeki dosyaları kullanır: `apple.png`, `apple_hover.png`, `apple_selected.png` ve `gravel.png`, `gravel_hover.png`, `gravel_selected.png` (normal, fare üzerinde, seçili). Kendi görsellerinizle değiştirebilirsiniz.

## Fırçalar

Oyunun fırçaları fare altındaki kareyi iki kez sayar ve sol üst köşedeki bir kareyi atlar. Bu ayarla her fırça tam şekline kavuşur.

## Geri al ve yinele

Harita düzenleyicinin sol üst köşesinde iki ok düğmesi (arazi ve kale menülerinde): soldaki son işlemi geri alır, sağdaki yineler. En fazla 20 adım tutulur. Her tıklama ve basılı tutulan her fırça darbesi bir adımdır; değişiklik yapmayan tıklamalar adım eklemez. Geri aldıktan sonra yeni işlem yapmak yineleme geçmişini temizler; başka harita yüklemek geçmişi sıfırlar.

## Damlalık

Arazi düzenleyicinin sol sütununda fırça boyutunun üstünde yer alır. Seçildiğinde menünün üzerinde **Yükseklikler**, **Dokular**, **Nesneler**, **Tümü** satırı ve içerik satırı belirir.

- **Alma:** bir kareye tıklayın (damlalık tek kare gösterir).
- **Uygulama:** tıklayın veya sürükleyin; Yükseklikler dokuyu, Dokular yüksekliği bozmaz.
- **Nesneler:** bir bina, sur, ağaç veya kayaya tıklayın. Binalar ve surlar ait oldukları oyuncu için kendi düğmeleri gibi konur (arması seçilir); ağaçlar (tür, aşama veya kütük sayısı) ve kayalar (tür ve yön) kendi araçları gibi sürükleme, önizleme ve denetimlerle konur. Çıkınca önceki fırça, kaya dönüşü ve devrilmiş ağaç seçimi geri gelir.
- **Tümü** ayrıca ağaç veya 1×1 kayayı alıp fırça altındaki her uygun kareye yerleştirir.
- Yükseklikler deniz, kumsal, bataklık, hendek, kaya, sur veya binalara; dokular kaya, sur veya binalara uygulanmaz. Uçurum kayaları temizlenir ve dik kenarlarda yeniden oluşur. **Alt** tuşunu basılı tutmak tüm karelere yükseklik ve doku uygular (kayalar kalır; deneysel).
- Damlalığı veya türünü tekrar seçmek boşaltır. **P** damlalığı seçer ve türler arasında geçer. **Ctrl** basılı tutmak dolu damlalıkla yeni kare almayı sağlar; bırakınca tekrar uygular. Üç tuş da değiştirilebilir veya kapatılabilir.
- Geri al damlalık işlemlerini de geri alır.

## Menüyü her zaman güncel tut

Oyun düzenleyici menüsünü yalnızca fare üzerindeyken yeniden çizer. Fare haritadayken bir değişiklik olduğunda (kısayol, sayaç değişimi) menü güncel kalmaz. Bu ayarla harita düzenleyicide menü sürekli güncellenir; düzenleyici dışında hiçbir şeyi değiştirmez.

## Kaynak ızgarası

Yapay zekânın taş ocakları, demir madenleri, zift kuyuları ve oduncuları için yer ararken
kullandığı 5 × 5 karelik bloklardan oluşan ızgarayı harita üzerine çizer. Tek bir blok içindeki
taş yatağı, yapay zekâ için aynı yatağın dört bloğa yayılmış hâlinden daha değerlidir. Ayrıca
yapay zekânın kale planının iç kalenin konumuna göre döndüğü dört çizgiyi ve her blokta bir
yapay zekâ demir madeninin kaplayacağı kareleri de çizer.

- **Alt + G** harita düzenleyicide bunu gösterir veya gizler. Ayarlardan başka bir Alt + tuş
  seçilebilir ya da kısayol Custom Hotkeys içinde değiştirilebilir.
- Varsayılan olarak yalnızca çizgilerin zemine tam oturduğu düzleştirilmiş görünümde (Boşluk
  tuşu) gösterilir ve V görünümünde gizlenir.
- **Oyun sırasında ızgaraya izin ver**, bir deneme oyununda çizgileri kontrol etmenizi sağlar.
- Izgaranın, sınırların ve maden alanının renkleri değiştirilebilir.
- Haritaya hiçbir şey kaydedilmez.

## Bilmekte fayda var

- Stronghold Crusader ve Stronghold Crusader Extreme ile çalışır; sınırlar oyundan okunduğu için Extreme kendi yüksek birim sınırını gösterir.
- Ağaçlar, çalılar ve kayalar oyun listelerindeki yuvalarına göre sayılır; üst üste yığılmış çalıların her biri sayılır.
- Harita dosyasına ek bir veri kaydedilmez.
