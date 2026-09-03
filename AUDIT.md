# Технічний аудит — PDF Scan & Convert Pro

Дата: 2026-09-03 · Версія на момент аудиту: 1.4 (build 1) · Обсяг: 37 Swift-файлів, ~12 573 рядки

---

## 0. Короткий вердикт

Типовий «paywall-first» скан-конвертер, зібраний швидко і місцями недбало. Функціонально працює, але:

- Щонайменше **3 баги, через які користувач може заплатити і не отримати доступ** — прямі втрати грошей, 1★ відгуки, рефанди.
- У репозиторії лежав **приватний RSA-ключ підпису коду у відкритому вигляді** (`codemagic.yaml`). Прибрано в цьому коміті — ключ треба відкликати.
- Мінімум **2 речі, за які Apple реально ріже апдейти**: рейтинг-гейтинг і кнопка, яка показує користувачу «TODO».
- Архітектурно: 3 God-об'єкти по ~1300–1400 рядків із масовим copy-paste, ~500 рядків мертвого коду, нуль локалізації, нуль тестів.

---

## 1. Безпека і секрети

### 1.1 Приватний RSA-ключ code signing у репозиторії — КРИТИЧНО

`codemagic.yaml:11-40` — `CERTIFICATE_PRIVATE_KEY` містив повний `-----BEGIN RSA PRIVATE KEY-----` у plaintext.

Хто завгодно з доступом до репо міг підписувати IPA від імені команди `SY7683D43P`. Якщо репо шарилось із фрилансерами — ключ вважати скомпрометованим.

**Дія:** відкликати сертифікат в Apple Developer → згенерувати новий → перенести в Codemagic Environment Variables (secure, група `appstore_signing`). Ключ уже був у zip до створення репо, тож історія git тут чиста, але сам сертифікат — ні.

### 1.2 Інше

| Що | Файл | Статус |
|---|---|---|
| Adapty public SDK key `public_live_F7MwJICF…` | `AppConstants.swift:13` | ОК — публічний за дизайном |
| Firebase `API_KEY`, `PROJECT_ID = pdfscanconvertpro` | `GoogleService-Info.plist` | Норма для iOS, але перевірити API key restrictions + Security Rules |
| App Store Connect integration `"Bhalat Puneey"` | `codemagic.yaml:7` | Акаунт продавця — перепідключити |
| Support email `bhalatpuneey@gmail.com` | `SettingsViewController.swift:45` | **Уся підтримка йде на пошту продавця. Змінити.** |
| App Store ID `6758149297` | `SettingsViewController.swift:42` | Захардкожений |

---

## 2. Монетизація — тут прямі втрати грошей

### 2.1 Покупка через StoreKit-fallback НЕ вмикає преміум

`StoreKitPaywallViewController.swift:541-544`

```swift
private func handleSuccessfulPurchase() {
    onPurchaseSuccess?()
    onClose?()
}
```

Ніде не оновлюється `SubscriptionManager.isPremiumActive`. Далі `MainViewController.swift:1362-1368` після `.purchased` викликає `updatePremiumStatus()` → `Adapty.getProfile()`. Але покупка зроблена «сирим» StoreKit 2 в обхід Adapty SDK — Adapty дізнається про неї лише через App Store Server Notifications, і то не миттєво. Якщо S2S у Adapty не налаштовані — **не дізнається ніколи**.

Результат: гроші списані, `isPremiumActive == false`, юзер лишається за пейволом. **Найдорожчий баг у проєкті.**

Фікс: після успішної StoreKit-покупки викликати `Adapty.restorePurchases()` або хоча б примусово виставити локальний преміум + додати `Transaction.updates` listener.

### 2.2 Подвійний виклик колбеків

Там же (`:541-544`): `onPurchaseSuccess?()` і `onClose?()` викликаються обидва. У `SceneDelegate.swift:343-355` і `:417-427` обидва роблять `dismiss(animated:)` + `startRatingTimerIfNeeded()` → подвійний dismiss і подвійний таймер. У `SubscriptionManager.swift:470-482` те саме: `completion` викликається двічі.

### 2.3 Adapty-пейвол: покупка пройшла, юзер зависає

`AdaptyPaywallViewController.swift:284-298` — немає `else` після перевірки `isPremiumActive`. Якщо профіль не встиг оновитись (мережа/лаг), пейвол просто лишається відкритим без повідомлення. Юзер тисне «купити» ще раз.

### 2.4 Немає listener'а `Transaction.updates`

0 збігів по всьому проєкту. Наслідки:

- Deferred purchases (Ask to Buy) ніколи не обробляються.
- Транзакції не завершуються (`finish()`) поза активним екраном → App Store повторно показує запит при кожному запуску.
- `AppDelegate.swift:372` `shouldAddStorePayment` повертає `true` (promoted IAP), але обробника немає.

### 2.5 Продукти з trial можуть не існувати

`StoreKitPaywallViewController.swift:24-56` — 6 product ID: `premium.{weekly,monthly,yearly}` + `.trial`-версії. Кнопка «Continue» вмикається, якщо завантажився **хоч один** продукт (`:437-440`). Якщо `premium.yearly.trial` не створений/не approved — кнопка активна, ціни нема, тап → `showError("Product not found")` (`:453-455`).

**Перевірити в App Store Connect, що всі 6 ID існують і активні.**

### 2.6 `SubscriptionManager.initialize()` не викликається ніде

0 збігів. Наслідки:

- `isReady` завжди `false`.
- **Прелоад конфігурацій пейволів (`:125-138, 250-267`) ніколи не відбувається**, кеш (`:271-290`) завжди порожній.
- Кожне відкриття пейвола = холодні послідовні запити `getPaywall` → `getPaywallProducts` → `getPaywallConfiguration`. Саме тому 12-секундний таймаут (`AdaptyPaywallViewController.swift:20`) і StoreKit-фолбек спрацьовують значно частіше, ніж мали б.
- ~150 рядків кешу/прелоаду/retry — мертвий код.

### 2.7 Обхід пейволу через UserDefaults — можливий офлайн

`SubscriptionManager.swift:64-69, 108` — `isPremiumActive` у plain UserDefaults без обфускації.

Онлайн обхід самолікується (`updatePremiumStatus()` перезаписує). **Офлайн (Airplane Mode) — працює**: `getProfile()` падає по таймауту, у `catch` (`:160-164`) статус не змінюється, кешоване `true` лишається. Jailbreak / plist-edit / backup-edit + офлайн = повний доступ.

Не масова загроза для утиліти, але схема «джерело істини — UserDefaults» неправильна. Мінімум — Keychain.

### 2.8 Фриз UI до 10 секунд

`MainViewController.swift:1336-1345` / `FolderViewController.swift:1236-1245`:

```swift
view.isUserInteractionEnabled = false
await SubscriptionManager.shared.updatePremiumStatus()   // withTimeout(10s) + retry
```

Офлайн або при поганій мережі кожен тап по документу = **до 10 секунд замороженого екрана без індикатора**. Для платного юзера в метро апка виглядає зламаною.

### 2.9 Restore purchases — є, але слабко

- StoreKit-пейвол: кнопка є (`:245-254`, логіка `:503-539`) — але **не оновлює `SubscriptionManager`**, та сама проблема, що й 2.1.
- Adapty-пейвол: обробник є (`:315-351`), але кнопка з'явиться, **лише якщо додана в шаблоні Adapty Dashboard** — перевірити для кожного placement.
- **У Settings кнопки «Restore Purchases» немає взагалі** (`SettingsViewController.swift:92-111`). Для юзера після перевстановлення шлях = «Premium Subscription» → чекати пейвол → шукати restore. UX-проблема + ризик по 3.1.1.

### 2.10 Карта монетизації — де гейтяться фічі

| Дія | Платно? | Файл |
|---|---|---|
| Сканування (VisionKit) | безкоштовно | `MainViewController.swift:700` |
| Камера + кроп → PDF | безкоштовно | `:735, :1380` |
| Галерея → PDF | безкоштовно | `:710` |
| Імпорт файлів → PDF | безкоштовно | `:727` |
| Web page → PDF | безкоштовно | `WebPageConverterViewController.swift:521` |
| Папки: створити/перейменувати/видалити | безкоштовно | `:668, :969, :989` |
| **Відкрити документ (перегляд)** | **PREMIUM** | `MainViewController.swift:1320`, `FolderViewController.swift:1220` |
| **Поділитись** | **PREMIUM** | `:1072, :511` / `FolderVC:1125, :943` |
| Друк | безкоштовно (всередині Detail, що вже за пейволом) | `DocumentDetailViewController.swift:226` |
| Перейменувати/видалити/перемістити документ | безкоштовно | різні |

**Модель: створювати можна все, ДИВИТИСЬ — ні.** Юзер сканує паспорт, тисне на файл — пейвол. Працює на конверсію, але дає високий refund rate, токсичні відгуки і потенційний привід для рев'юера («app is not functional without purchase»).

---

## 3. Ризики App Store Review

### 3.1 Рейтинг-гейтинг — пряме порушення 1.1.7

`RateAppViewController.swift:266-289`

```swift
if rating <= 3 {
    // показуємо «дякуємо» і закриваємо — в App Store НЕ відправляємо
} else {
    requestInAppReview()   // SKStoreReviewController
}
```

До App Store потрапляють тільки 4–5 зірок. Apple прямо забороняє (Guideline 1.1.7, «Do not attempt to manipulate reviews… including by filtering»). За це ріжуть апдейти, зрідка знімають апку.

Фікс: показувати `SKStoreReviewController` усім незалежно від оцінки, або прибрати кастомний зоряний екран.
Додатково: `SKStoreReviewController.requestReview(in:)` deprecated з iOS 18 → `AppStore.requestReview(in:)`.

### 3.2 Кнопка, яка показує «TODO»

`FolderViewController.swift:822-824`

```swift
case .webPage:
    showAlert(title: "Web Page", message: "TODO")
```

Усередині папки пункт меню «Web Page» показує алерт зі словом TODO. Функціональний баг + Guideline 2.1/2.3 (placeholder content). Рев'юер точно клікне.

### 3.3 Пейвол при КОЖНОМУ виході з фону

`SceneDelegate.swift:65-79` — `showLaunchPaywallIfNeeded` викликається з `sceneDidBecomeActive`, а не з `willConnectTo`. При `show_paywall_on_launch = true` у Remote Config юзер отримує повноекранний пейвол щоразу, повертаючись у апку.

Гірше: guard «не показувати в першу сесію» зламаний — `:66-69` скидає прапорець `isFirstSessionAfterOnboarding` **синхронно на початку методу**, а перевіряється він (`:272`) вже після `await updatePremiumStatus()`. На момент перевірки прапорець завжди `false`.

Ризик: Guideline 3.1.2 / «aggressive monetization» + дуже погані метрики retention.

### 3.4 Пейвол не показує обов'язкові дані про підписку

`StoreKitPaywallViewController.swift:119-254`. Є: заголовок, ціна, Terms, Privacy, Restore. **Немає**: явного тексту про довжину періоду, автопродовження, перехід тріалу в платну підписку, скасування в налаштуваннях. Apple вимагає ці дисклеймери на екрані покупки. У кнопках лише «Yearly / $X» — цього мало.

Adapty-пейвол — залежить від шаблону в дашборді, перевірити окремо.

### 3.5 Terms/Privacy на telegra.ph

`StoreKitPaywallViewController.swift:585, 589`, `SettingsViewController.swift:270, 276`:

```
https://telegra.ph/Terms-of-Use--PDF-Scan--Convert-Pro-01-27
https://telegra.ph/Privacy-Policy--PDF-Scan--Convert-Pro-01-27
```

Лінки є (плюс), але telegra.ph — анонімний паблішинг, сторінку може видалити хто завгодно з ключем редагування, і вона не прив'язана до нас як власника. Перенести на власний домен (`pdfscanconvert.site`).

### 3.6 Дозволи (Info.plist)

- `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSUserTrackingUsageDescription` — є, формулювання нормальні.
- `NSPhotoLibraryAddUsageDescription` — **зайвий**, апка ніде не зберігає в фотогалерею. Видалити.
- Ті самі ключі **дублюються** в build settings (`project.pbxproj:189-190`) з **іншим текстом**. Лишити одне джерело.
- Відсутній `ITSAppUsesNonExemptEncryption` → Apple питатиме про шифрування на кожному аплоаді. Додати `<false/>`.

### 3.7 ATT через 1 секунду після старту

`AppDelegate.swift:130-141` — ATT-промпт стріляє через 1 с після `didBecomeActive`, паралельно з онбордингом/пейволом. Три системні модалки одна на одній → низький opt-in rate.

### 3.8 Необмежений веб-браузер усередині апки

`WebPageConverterViewController.swift:191-199, 493-519` — WKWebView відкриває будь-який URL без фільтрів. Формально це необмежений доступ до вебу → Apple зазвичай вимагає age rating 17+ або content filtering. Перевірити поточний age rating.

---

## 4. Реальні баги

### 4.1 Race condition при імпорті з галереї

`MainViewController.swift:1231-1252` (дослівно те саме в `FolderViewController.swift:732-753`):

```swift
var images: [UIImage] = []
for result in results {
    group.enter()
    result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
        defer { group.leave() }
        if let img = obj as? UIImage { images.append(img) }   // ← з різних потоків
    }
}
```

`loadObject` викликає колбек на довільних фонових чергах, паралельно. `Array.append` не потокобезпечний → у кращому випадку сторінки в PDF у випадковому порядку, у гіршому — `EXC_BAD_ACCESS`.

Фікс: `[UIImage?](repeating: nil, count: results.count)` + запис за індексом.

### 4.2 Два різні шляхи зберігання PDF

- `FileManagerHelper.swift:17-21` + `DocumentManager.swift:186-189` → `Documents/PDFs/<file>.pdf`
- `MainViewController.swift:800-803`, `FolderViewController.swift:562-565`, `DocumentDetailViewController.swift:171-175`, `WebPageConverterViewController.swift:603` → `Documents/<file>.pdf` (корінь)

Зараз не стріляє лише тому, що `DocumentManager` (285 рядків) — **мертвий код**. Але щойно хтось «підключить менеджер, він же для цього й написаний» — документи стануть невидимі для екранів деталей, а видалення папки не видалятиме файли з диска.

### 4.3 `fatalError` на завантаженні Core Data

`CoreDataStack.swift:20-21`

```swift
container.loadPersistentStores { storeDescription, error in
    if let error { fatalError("Core Data load error: \(error)") }
```

Будь-яка зміна моделі без коректної lightweight-міграції, пошкоджений store, повний диск → апка крешиться при старті **у всіх наявних юзерів, назавжди**. Перевстановлення = втрата всіх сканів. Для проданої апки з активною базою це головна бомба сповільненої дії.

### 4.4 Робота з видаленою `CDFolder`

`FolderViewController` тримає сильне посилання на `folder: CDFolder` (`:30`) і підписаний на `NSManagedObjectContextObjectsDidChange` (`:231-239`) → `loadData()` → `fetchDocuments(in: folder)` (`:458-465`) і `folder.name` (`:297`). Якщо папку видалили, а контролер ще в стеку — `NSObjectInaccessibleException`. Немає перевірки `folder.isDeleted`.

### 4.5 `reloadData()` на кожну зміну Core Data

`MainViewController.swift:201-212`, `FolderViewController.swift:231-239`.

- Кожне збереження = повний рефетч бази + перемальовка колекції.
- **Скидається фокус у полі пошуку**: `searchView` у supplementary header (`:876`), при `reloadData()` header перестворюється → клавіатура закривається під час набору.
- Гонка з `performBatchUpdates` (`:642-651`, `:1050-1057`, `:1164-1171`) → класичний `NSInternalInconsistencyException: invalid number of items in section`.

Фікс: `NSFetchedResultsController` — прибирає ~300 рядків дублювання і всі ці гонки одночасно.

### 4.6 Витік дочірнього контролера пейволу

`AdaptyPaywallViewController.swift:56-61` — `paywallController = nil` без `willMove(toParent: nil)` / `removeFromSuperview()` / `removeFromParent()`. У `AdaptyOnboardingViewController.swift:217-223` це зроблено правильно — там і подивитись, як має бути.

### 4.7 Force unwrap / KVO

- `SubscriptionManager.swift:421` — `try await group.next()!` (не стрельне, але поганий стиль у критичному місці)
- `WebPageConverterViewController.swift:603` — `urls(...).first!`
- `WebPageConverterViewController.swift:367 / :692` — KVO `estimatedProgress` додається в `setupUI()`, знімається в `deinit`. Якщо VC задеалоковано без `viewDidLoad` — креш «not registered as an observer». Краще `NSKeyValueObservation`.
- `DocumentDetailViewController.swift:501` — force unwrap констрейнтів

### 4.8 Підозріле: `cropVC.aspectRatioPreset = normalized.size`

`MainViewController.swift:1387`, `FolderViewController.swift:1305`. У TOCropViewController 3.1.1 `aspectRatioPreset` — це enum, а не `CGSize` (для CGSize є `customAspectRatio`). У коді навіть є коментар «У твоїй версії це CGSize».

Або в проєкті є локальний форк, або **цей код не компілюється**. Перевірити першим ділом при спробі зібрати.

### 4.9 Retain cycles

Відносно чисто — `[weak self]` розставлений майже всюди. Класичних циклів, що течуть, не знайдено. Дрібне:

- `SceneDelegate.swift:502-504, 509-516` — сильний `self` в анімаціях (не леак, SceneDelegate живе весь час)
- `FolderViewController.swift:1206-1210` — сильний `self` у completion `performBatchUpdates`, неконсистентно з сусідніми методами
- `StoreKitPaywallViewController.swift:427-449, 461-500, 506-538` — `Task { … self.… }` без weak: UI-оновлення прилітають у вже закритий контролер

---

## 5. Що апка робить функціонально

**Джерела контенту (усі безкоштовні):**

1. Сканування — `VNDocumentCameraViewController` (автообрізка, перспектива)
2. Камера → кроп (TOCropViewController) → PDF
3. Галерея (PHPicker, ліміт 10 на головному / 20 у папці) → PDF
4. Імпорт файлів (`UIDocumentPicker`: pdf, image, jpeg, png) → PDF
5. Web page → PDF (`WKWebView.createPDF`) — тільки з головного екрана; у папці «TODO»

**Організація:** папки (створення/перейменування/видалення з каскадом), документи в папках або в «Home», переміщення (`MoveToFolderViewController`), мультивибір (share/move/delete), сортування (name A-Z/Z-A, date new/old), пошук по назві (тільки по кнопці).

**Перегляд:** PDFKit-в'ювер з лічильником сторінок, перейменування, друк, шеринг, видалення.

**Чого НЕМАЄ — важливо для оцінки того, що куплено:**

- ❌ **OCR / розпізнавання тексту** — `VNRecognizeTextRequest` не використовується, `Vision` не імпортується
- ❌ **E-signature**
- ❌ **Merge/split PDF, reorder сторінок, компресія** — хоча онбординг обіцяє «Combine pages, reorder them» (`DefaultOnboardingViewController.swift:42`). Це **неправдиве твердження в онбордингу** — ще й привід для рев'ю
- ❌ Фільтри/покращення сканів (ч/б, контраст)
- ❌ Пароль на PDF, iCloud-синк, експорт у Word/Excel

Конкурентна «начинка» відносно CamScanner/Adobe Scan — мінімальна. OCR + merge/reorder + фільтри — це те, чого юзери очікують і за що платять.

**Аналітика/атрибуція:** Firebase Analytics + Remote Config, Adapty, Apple Search Ads (`AdServices`, `AppDelegate.swift:230-323`), IDFA/ATT, зв'язка Firebase `appInstanceID` ↔ Adapty. Ця частина зроблена якраз непогано.

---

## 6. Архітектура і технічний борг

### 6.1 Massive View Controllers + масовий copy-paste

`MainViewController` (1421) і `FolderViewController` (1340) — **~70% дослівно однаковий код**:

| Дублікат | MainVC | FolderVC |
|---|---|---|
| `requirePremium(...)` | `:1332-1374` | `:1232-1274` |
| `sortDocuments(by:ascending:)` | `:496-509` | `:934-941` |
| `sortButtonTapped` | `:433-476` | `:884-927` |
| `selectButtonTapped` | `:380-431` | `:835-871` |
| `updateActionButtons` | `:654-664` | `:873-882` |
| `performDelete` | `:616-652` | `:1040-1084` |
| `moveSelectedDocuments` | `:547-596` | `:972-1020` |
| `persistPDF` / `pdfURL` / `makePDFThumbnail` / `deletePDFFileIfNeeded` | `:756-814` | `:530-597` |

Причому дублікати **розійшлися в поведінці**: `MainViewController.makePDFDataFromImagesOriginalSize` (`:1216-1219`) робить PDF в **оригінальному розмірі зображення**, а `FolderViewController.makePDFData` (`:573-592`) — у **A4 595×842**. Скан із головного екрана і скан із папки дають PDF різного формату. Це справжній баг.

`RootTabBarController` (1337) — власна реалізація `UITabBarController` з нуля (кастомний dock-таббар з центральною кнопкою, KVO на tabBarItem, transitions, badge API). Написано непогано, але це ще 1300 рядків на супровід.

**Що рефакторити першим (користь/ризик):**

1. `DocumentsListViewController` — спільна база для Main+Folder (−~700 рядків)
2. `PremiumGate` — один сервіс замість двох копій `requirePremium` (+ фікс фризу і StoreKit-синхронізації)
3. `PDFFactory` — одна реалізація image→PDF (вирішити: оригінал чи A4)
4. `NSFetchedResultsController` замість ручних масивів + обсервера (−~300 рядків і всі гонки з 4.5)
5. Видалити мертвий код: `DocumentManager.swift` (285), `RatingManager.swift` (40, повністю закоментований), невживані частини `FileManagerHelper`, prefetch/кеш `SubscriptionManager` — або нарешті викликати `initialize()`

### 6.2 Deployment target: 15.0 vs 26.2

`project.pbxproj`: target-рівень (рядки 197, 236) — `15.0`; project-рівень (309, 367) — `26.2`.

Target перекриває project, тому зараз збирається під iOS 15.0 і працює. Але project-рівень 26.2 — міна: будь-який новий таргет (extension, widget, тести) успадкує 26.2. Привести до одного. Рекомендація: підняти до 16.0–17.0 (частка iOS 15 — частки відсотка).

### 6.3 Swift 5.0 + суперечливі налаштування конкурентності

`SWIFT_VERSION = 5.0`, але в тій же конфігурації `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` — налаштування Swift 6-ери на Swift 5 language mode (`LastUpgradeCheck = 2620`).

Робоче, але крихке: при переході на Swift 6 mode код із `Task { self... }` і несинхронізованими масивами (4.1) посиплеться сотнями помилок. Планувати окремим етапом.

### 6.4 Storyboard vs код

UI на 99% кодовий. `Main.storyboard` існує і прописаний як `UISceneStoryboardFile` + `INFOPLIST_KEY_UIMainStoryboardFile`, але `SceneDelegate.willConnectTo` (`:44-53`) одразу створює власне `UIWindow` і підміняє root. Storyboard **інстанціюється і викидається** на кожному запуску. Прибрати ключі й файл (`LaunchScreen.storyboard` лишити).

### 6.5 Локалізація — відсутня повністю

- `NSLocalizedString` — **0 збігів**
- Немає `.strings` / String Catalog, немає `CFBundleLocalizations`
- Усі рядки зашиті англійською: `"Scans"`, `"Delete Items"`, `"Are you sure you want to delete \(count) item(s)?"` тощо
- Плюралізація руками: `DocumentCollectionCell.swift:151` — `"\(pageCount) page" + (pageCount == 1 ? "" : "s")` — таке в принципі не локалізується без переписування
- Пейволи Adapty жорстко на `"en"`: `SubscriptionManager.swift:200, 252`

Вихід на не-англомовні ринки = переписування всіх ~250 user-facing рядків. Окремий проєкт на 1–2 тижні.

### 6.6 Дрібніше, але варте фіксу

- **Dark Mode не застосовується при запуску.** `SettingsViewController.swift:165-180` зберігає прапорець і застосовує `overrideUserInterfaceStyle`, але ніде немає виклику при старті. Юзер вмикає темну тему → перезапускає апку → тема скинулась.
- **Пошук лише по кнопці** (`SearchFieldView.swift:67-76` + `MainViewController.swift:63-88`), юзери очікують live-search.
- **Пошук фільтрує в пам'яті**, а не в базі (`:79-82`) — при тисячах документів помітно.
- **Мініатюри в SQLite**: `thumbnailData` — Binary **без** `allowsExternalBinaryDataStorage`, JPEG 0.85–0.92 (`:778`, `WebPageConverterViewController.swift:620`) → десятки КБ на документ прямо в базі, `fetch` сповільнюється. Увімкнути external storage.
- **PDF з зображень без даунскейлу** (`:1207-1219`): 10 фото по 12 Мп → PDF на 40–60 МБ + піковий сплеск пам'яті → OOM-kill на старших пристроях.
- **Файли не виключені з iCloud-бекапу** — усе в `Documents/` без `isExcludedFromBackupKey`. Скани роздувають бекап. Вирішити свідомо (аргумент «це користувацькі дані» теж валідний).
- **~60 `print()` у продакшні**, зокрема логування URL сторінок (`WebPageConverterViewController.swift:506, 722, 728`), IDFA (`AppDelegate.swift:200`), Firebase instance ID (`:114`). Загорнути в `#if DEBUG`.
- **`TARGETED_DEVICE_FAMILY = 1`** (тільки iPhone), але прописані iPad-орієнтації і є iPad popover-логіка (`SettingsViewController.swift:338-343`).
- **`sortDocuments` через KVC** (`value(forKey:)`) замість keypath — впаде рантаймом при перейменуванні атрибута.
- **Немає жодного тесту** — ні unit, ні UI, таргетів тестів немає взагалі.

---

## 7. Пріоритезований план

### Цього тижня — гроші й безпека

1. Відкликати й перевипустити code-signing сертифікат; ключ уже винесено з `codemagic.yaml` у групу `appstore_signing` *(1.1)*
2. Пофіксити StoreKit-fallback: синхронізувати з Adapty після покупки/restore; прибрати подвійні колбеки; додати `else` у `didFinishPurchase` *(2.1–2.3)*
3. Додати глобальний `Transaction.updates` listener *(2.4)*
4. Перевірити в App Store Connect всі 6 product ID *(2.5)*
5. Замінити support-email на свій *(1.2)*

### Перед наступним сабмітом — щоб не зарізали

6. Прибрати рейтинг-гейтинг *(3.1)*
7. Прибрати «TODO» у папці *(3.2)*
8. Прибрати з онбордингу обіцянку reorder/combine pages *(розд. 5)*
9. Додати дисклеймери про автопродовження на StoreKit-пейвол; те саме перевірити в Adapty-шаблонах *(3.4)*
10. Додати «Restore Purchases» і «Manage Subscription» у Settings *(2.9)*
11. Перенести Terms/Privacy на власний домен *(3.5)*
12. Пофіксити launch-paywall: холодний старт замість кожного foreground; полагодити first-session guard *(3.3)*

### Найближчий місяць — стабільність

13. Race condition у PHPicker (обидва екрани) *(4.1)*
14. Прибрати `fatalError` у CoreDataStack, додати recovery *(4.3)*
15. Викликати `SubscriptionManager.initialize()` при старті + прибрати 10-секундний фриз *(2.6, 2.8)*
16. Захист від видаленої `CDFolder` *(4.4)*
17. `removeFromParent` у пейволі; перевірити компільованість `aspectRatioPreset` *(4.6, 4.8)*
18. Уніфікувати шляхи зберігання PDF, видалити мертвий `DocumentManager` *(4.2)*
19. Пофіксити Dark Mode при запуску *(6.6)*

### Далі — борг і зростання

20. Рефакторинг Main/Folder у спільну базу + `NSFetchedResultsController` *(6.1)*
21. Локалізація (String Catalog) *(6.5)*
22. Вирівняти deployment target, спланувати Swift 6 *(6.2–6.3)*
23. Функціонал, за який реально платять: OCR (Vision), merge/reorder/split, фільтри сканів, компресія *(розд. 5)*
