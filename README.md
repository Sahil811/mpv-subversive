# mpv-subversive

https://github.com/user-attachments/assets/00b0fa29-70e3-4cf9-8637-c21c13af37fb

A powerful, cross-platform (Windows & GNU/Linux) MPV plugin that makes it seamless to find, download, and load subtitles for the anime you're watching. 

This is an actively maintained and deeply improved fork of the original mpv-subversive.

## ✨ Features & Improvements

- **Full Windows & Linux Support:** Works seamlessly across OS boundaries without buggy sub-processes.
- **Auto-Detection:** Automatically parses your video file names, strips out noise (e.g., `[1080p]`, `[HEVC]`), and identifies the Anime title and episode.
- **AniList Integration:** Queries the AniList GraphQL API to accurately identify the series.
- **Dual Subtitle Backends:**
  - **Jimaku (Online):** Downloads subtitles on-the-fly using the Jimaku API.
  - **Offline Mode:** Uses a local CSV mapping to load your locally stored subtitles instantly without an internet connection.
- **Sleek UI:** Fully modernized GUI menu for subtitle selection.
- **Robust Error Handling:** Avoids LuaJIT crashes, handles API timeouts gracefully, and features proper network retry logic.

For a complete list of changes, see [IMPROVEMENTS.md](./IMPROVEMENTS.md).

## 🚀 Quickstart & Installation

Please see our comprehensive **[QUICKSTART.md](./QUICKSTART.md)** for installation instructions, including how to install dependencies (`7zip`, `unrar`, `luarocks`, etc.) on both Windows and Linux.

### Basic Installation
```sh
# Clone directly to your MPV scripts folder
git clone https://github.com/Sahil811/mpv-subversive.git ~/.config/mpv/scripts/mpv-subversive
```

## 📖 Usage & Configuration

Press `b` (for **b**rowse) while watching a video to open the subtitle menu! 

If the script can't auto-detect the anime from the filename, it will prompt you to type the name manually (requires MPV v0.38.0+).

For full details on configuration files (`mpv-subversive.conf`), keyboard shortcuts, API key setup, and offline mode configuration, please read our **[USAGE.md](./USAGE.md)**.

## 🤝 Dependencies

- `unrar`, `unzip`, `7zip` (to extract archives)
- `luasocket`, `luasec` (optional for faster networking, falls back to `curl` automatically)

## 📜 Credits

- Original code by [nairyosangha](https://github.com/nairyosangha/mpv-subversive)
- GUI menu logic originally inspired by [autosubsync-mpv](https://github.com/joaquintorres/autosubsync-mpv)
- Metadata provided by [AniList API](https://anilist.gitbook.io/anilist-apiv2-docs/overview/graphql)
- Subtitles provided by [Jimaku.cc](https://jimaku.cc)
