[![PayPal Donation](https://github.com/Daniel20Ultrastar-es/WorldParty-testing/blob/master/promo/Donate-Paypal.svg)](https://www.paypal.com/cgi-bin/webscr?item_name=Ultrastar+Espa%f1a+&cmd=_donations&currency_code=EUR&business=donaciones%40ultrastar-es.org)
[![ultrastar-worldparty](https://snapcraft.io/ultrastar-worldparty/badge.svg)](https://snapcraft.io/ultrastar-worldparty)
[![ultrastar-worldparty](https://snapcraft.io/ultrastar-worldparty/trending.svg?name=0)](https://snapcraft.io/ultrastar-worldparty)

# UltraStar WorldParty


![WorldParty logo](https://github.com/Daniel20Ultrastar-es/usdxworldparty/blob/master/promo/Worldparty%20logo.png)

UltraStar WorldParty is a free and open source karaoke game.  It allows
up to six players to sing along with music using microphones in order to
score points, depending on the pitch of the voice and the rhythm of
singing.

UltraStar WorldParty is a fork of the original UltraStar Deluxe 1.1
We added new features such as new selection song, avatars, themes,
skins, font, improved camera and mouse support, thousands of new options
come with this new version. Check it out!

-----------------
Official Website:  https://ultrastar-es.org
-----------------

## Documentation
Visit our [Wiki](https://github.com/ultrastares/ultrastar-worldparty/wiki) to get help about how to compile the game, see changelog, etc..

## Song directories

The game reads its settings from `config.ini`. When installed with the
installer, the file lives in the per-user application data folder
(`%APPDATA%\WorldParty` on Windows); when the game folder itself is
writable (portable use), it sits next to the executable instead.

Song folders are configured in the `[Directories]` section:

```ini
[Directories]
SongDir1=D:\Karaoke\Library
DynamicSongDir1=D:\Karaoke\Incoming
DisabledSongDir=D:\Karaoke\Trash
```

* `SongDir1`..`SongDirN` — static song libraries ("standard" folders).
  They are scanned once at startup. Any number of entries can be added.
* `DynamicSongDir1`..`DynamicSongDirN` — directories whose content
  changes at runtime, for example a folder that other tools drop new
  songs into while the game is running.
* `DisabledSongDir` — the trash folder used by the "disable song"
  feature in the song menu: the song's folder is moved there and the
  song disappears from the library without deleting any files. Move it
  back manually to re-enable it. The folder must be on the same drive
  as the song directories and must not lie inside one of them.

### Managing song folders in the game

**Options → Song folders** lists all song folders, including the
built-in ones that are always scanned (such as `songs` next to the
configuration):

* **Add standard folder** / **Add dynamic folder** open a folder browser
  that works with keyboard, mouse and controller. It lists the drives
  and subfolders; **Ctrl+V** pastes a path, which also allows network
  shares like `\\server\share`.
* **Enter** on the type of a folder switches between standard and
  dynamic, **Enter** on the path picks another folder, and the delete
  button (or the **Del** key) removes the folder from the list. The songs
  on disk are never touched.
* Folders that contain each other, or the trash folder, are rejected,
  because their songs would be loaded twice.

Leaving the screen saves the changes to `config.ini` and rescans the
songs: only the dynamic folders when nothing else changed, otherwise
everything. If a scan is still running, the rescan follows automatically
once it has finished and the main menu is shown.

### Rescanning at runtime

* **F5** (in the main menu or the song screen) rescans **only the
  dynamic song directories** — new songs appear, removed ones vanish,
  and the static libraries are not touched, no matter how large they
  are. The song menu entry "Search for new songs" does the same.
* **Shift+F5** rescans everything, including the static libraries.
* The song menu also offers a source filter (all / standard / dynamic
  songs) to limit the shown songs to one kind of directory.

## Support and contact
Visit our [official website](https://ultrastar-es.org) where you can find tutorials, songs, contests and more

also visit our [forum](https://ultrastar-es.org/foro) where you can ask any problem or doubt you get (we speak mainly in Spanish and English)

## Screenshots
![WorldParty logo](https://github.com/Daniel20Ultrastar-es/usdxworldparty/blob/master/promo/promocion1.gif)

![WorldParty logo](https://github.com/Daniel20Ultrastar-es/usdxworldparty/blob/master/promo/promocion2.gif)

![WorldParty logo](https://github.com/Daniel20Ultrastar-es/usdxworldparty/blob/master/promo/promocion3.gif)
