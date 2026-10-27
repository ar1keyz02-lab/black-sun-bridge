# Black Sun Media Bridge

Optional helper for the **Black Sun** wallpaper for Wallpaper Engine (Steam Workshop).
Wallpapers can only *read* what is playing; this small PowerShell script lets the wallpaper's
player widget *control* playback.

[Русская версия ниже](#русский)

## What it adds

| Feature | Works without the helper |
| --- | --- |
| Track title, artist, cover, progress, lyrics from LRCLIB | yes |
| Previous / play-pause / next buttons, seek slider | no — needs the helper |
| Volume of the player app (like the Windows volume mixer) | no — needs the helper |
| Likes and synced lyrics from Yandex Music | no — needs the helper + a Yandex token |

Works with any player shown in the Windows volume flyout (Yandex Music, Spotify, browsers…).

## How it works and why it is safe

- It is plain text: `media-bridge.ps1` and `app-volume.cs` (Windows audio API, compiled on the fly by PowerShell). Read them before running.
- It listens only on `http://127.0.0.1:47811/` — reachable from your PC only.
- Playback commands go to Windows (System Media Transport Controls), volume goes to the app's own audio session.
- The Yandex token (optional) is stored encrypted with Windows DPAPI in `%APPDATA%\AR1KEYZ\bridge.json` — only your Windows account can decrypt it — and is sent only to `api.music.yandex.net`.
- Yandex Music features use its unofficial API and may stop working after Yandex updates.

## Install

1. Download this repository (**Code → Download ZIP**) and unpack it to a permanent folder, for example `C:\Tools\black-sun-bridge`.
2. In Wallpaper Engine settings → General turn on **Media integration**.
3. Optional, for Yandex Music likes and lyrics — save your token:
   ```
   powershell -ExecutionPolicy Bypass -File "C:\Tools\black-sun-bridge\media-bridge.ps1" -SetToken
   ```
   Open the link it prints, sign in, copy everything between `access_token=` and the first `&` from the address bar, paste it and press Enter (input is hidden).
4. Start the helper and add it to Windows startup:
   ```
   powershell -ExecutionPolicy Bypass -File "C:\Tools\black-sun-bridge\media-bridge.ps1" -Install
   ```
5. Check: `http://127.0.0.1:47811/status` in a browser shows the current track.

`-ExecutionPolicy Bypass` only lets this one script run without changing your system policy.

## Remove

```
powershell -ExecutionPolicy Bypass -File "C:\Tools\black-sun-bridge\media-bridge.ps1" -Uninstall
```
Then end the hidden `powershell.exe` running `media-bridge` in Task Manager and delete `%APPDATA%\AR1KEYZ`.

---

## Русский

Необязательный помощник для обоев **Black Sun** (Wallpaper Engine, Steam Workshop). Обои умеют только *читать*, что играет; этот скрипт PowerShell даёт плееру в обоях *управлять* воспроизведением.

### Что добавляет

| Функция | Работает без помощника |
| --- | --- |
| Название, исполнитель, обложка, прогресс, текст из LRCLIB | да |
| Кнопки «назад», «пауза», «вперёд», перемотка | нет — нужен помощник |
| Громкость самого плеера (как в микшере Windows) | нет — нужен помощник |
| Лайки и синхронный текст из Яндекс Музыки | нет — нужен помощник и токен Яндекса |

Работает с любым плеером из системной панели громкости Windows.

### Почему это безопасно

- Это обычный текст: `media-bridge.ps1` и `app-volume.cs`. Прочитайте их перед запуском.
- Помощник слушает только `http://127.0.0.1:47811/` — с других компьютеров к нему не подключиться.
- Токен Яндекса (по желанию) хранится зашифрованным средствами Windows в `%APPDATA%\AR1KEYZ\bridge.json` и отправляется только на `api.music.yandex.net`. Никому его не показывайте.
- Функции Яндекс Музыки работают через её неофициальный API и могут сломаться после обновлений Яндекса.

### Установка

1. Скачайте репозиторий (**Code → Download ZIP**) и распакуйте в постоянную папку, например `C:\Tools\black-sun-bridge`.
2. В Wallpaper Engine → настройки → General включите **Media integration**.
3. По желанию, для лайков и текстов из Яндекс Музыки — сохраните токен:
   ```
   powershell -ExecutionPolicy Bypass -File "C:\Tools\black-sun-bridge\media-bridge.ps1" -SetToken
   ```
   Откройте ссылку, которую покажет скрипт, войдите в Яндекс, скопируйте из адреса всё между `access_token=` и первым `&`, вставьте и нажмите Enter (ввод скрыт).
4. Запустите помощника и добавьте его в автозапуск:
   ```
   powershell -ExecutionPolicy Bypass -File "C:\Tools\black-sun-bridge\media-bridge.ps1" -Install
   ```
5. Проверка: `http://127.0.0.1:47811/status` в браузере показывает текущий трек.

### Подсказки в плеере

| Подсказка | Что сделать |
| --- | --- |
| BRIDGE OFFLINE / ПОМОЩНИК НЕ ЗАПУЩЕН | Шаг 4 |
| NO YANDEX TOKEN / НЕТ ТОКЕНА ЯНДЕКСА | Шаг 3, затем снова шаг 4 |
| YANDEX ERROR / ОШИБКА ЯНДЕКСА | Токен неверный или истёк — повторите шаг 3 и шаг 4 |

### Удаление

```
powershell -ExecutionPolicy Bypass -File "C:\Tools\black-sun-bridge\media-bridge.ps1" -Uninstall
```
Затем завершите в диспетчере задач скрытый `powershell.exe` с `media-bridge` и удалите папку `%APPDATA%\AR1KEYZ`.
