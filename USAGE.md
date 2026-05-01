# mpv-subversive - Enhanced Usage Guide

## Quick Start

1. **Configure your API token**
   - Create account at https://jimaku.cc/login
   - Generate API key at https://jimaku.cc/account
   - Add to config: `~/.config/mpv/script-opts/mpv-subversive.conf` (Linux) or `%APPDATA%/mpv/script-opts/mpv-subversive.conf` (Windows)
   
   ```ini
   API_TOKEN=your_token_here
   show_notifications=yes
   ```

2. **Use the plugin**
   - Press `q` while watching to open subtitle browser
   - Navigate with arrow keys or `j`/`k`
   - Press Enter or `l` to select subtitle
   - Press ESC or `n` to close menu

## Features

### Automatic Episode Detection
The plugin automatically detects episode numbers from filenames:
- `Show Name - 01.mkv` → Episode 1
- `Show Name S01E05.mkv` → Episode 5
- `[Group] Show Name 077 [1080p].mkv` → Episode 77
- `Show Name EP12.mkv` → Episode 12

### Smart Subtitle Matching
- Automatically highlights matching episodes with `[MATCH]` prefix
- Sorts matching subtitles to the top
- Supports multiple episode number formats
- Handles zero-padded numbers (01, 001, etc.)

### Download Management
- Shows download progress in real-time
- Automatic retry on failed downloads (configurable)
- Caches downloaded subtitles for reuse
- Extracts subtitle archives automatically

### Lookup Caching
When you identify a show, the plugin saves `.anilist.id` file in the video directory.
This means:
- No need to lookup each episode in a series
- Faster subtitle loading
- Works offline for cached subtitles

### Auto-Load Subtitles
Enable in config:
```ini
auto_load_subs=yes
```
Automatically loads matching subtitles when:
- `.anilist.id` file exists in directory
- Episode number is detected
- Matching subtitle is cached

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | yes | Enable/disable plugin |
| `chosen_sub_dir` | ./subs | Where to save selected subtitles |
| `cache_directory` | /tmp/subloader | Subtitle download cache |
| `enable_lookup_caching` | yes | Cache AniList lookups |
| `media_blacklist_dir` | "" | Exclude directories from caching |
| `subtitle_backend` | jimaku | Backend: jimaku or offline |
| `API_TOKEN` | "" | Jimaku API token (required) |
| `auto_load_subs` | no | Auto-load matching subtitles |
| `preferred_languages` | ja,jp,jpn | Preferred language codes |
| `show_notifications` | yes | Show OSD messages |
| `download_retry_count` | 3 | Retry failed downloads |
| `http_timeout` | 30 | HTTP timeout in seconds |

## Troubleshooting

### No subtitles found
- Check API token is correct
- Verify show name detection: check MPV console for parsed title
- Try manual lookup (first menu option)
- Check Jimaku.cc has subtitles for your show

### Episode not detected
- Check filename format
- Use manual episode number entry (second menu option)
- Check MPV console for detected episode number

### Download fails
- Check internet connection
- Verify API token is valid
- Check cache directory is writable
- Increase `download_retry_count`

### Subtitle doesn't load
- Verify subtitle file was downloaded (check cache directory)
- Check MPV console for errors
- Try manually selecting from menu
- Ensure subtitle format is supported by MPV

## Advanced Usage

### Manual Show Lookup
If automatic detection fails:
1. Press `q` to open menu
2. Select "Text-based lookup"
3. Type show name
4. Select from results with TAB
5. Press ENTER

### Manual Episode Number
If episode detection fails:
1. Press `q` to open menu
2. Select "Modify episode number"
3. Enter correct episode number
4. Press ENTER

### Toggle Show All Files
By default, only matching episodes are shown.
To see all subtitles:
1. Open subtitle menu
2. Select "Toggle showing all files"

### Save Subtitle Permanently
When you select a subtitle with ENTER:
- It's loaded into MPV
- If `chosen_sub_dir` is set, it's saved to that directory
- Saved with same name as video file

## Keyboard Shortcuts

In subtitle menu:
- `↑`/`k` - Move up
- `↓`/`j` - Move down
- `Enter`/`l` - Select and save subtitle
- `ESC`/`n`/`h` - Close menu

## Error Messages

| Message | Meaning | Solution |
|---------|---------|----------|
| "No API_TOKEN configured" | Missing API key | Add token to config |
| "Invalid API token" | Wrong API key | Check token at jimaku.cc |
| "No subtitles found" | No subs for this show | Try different show or check AniList ID |
| "Episode number not detected" | Filename parsing failed | Use manual episode entry |
| "Download failed" | Network/server error | Check connection, retry |

## Tips

1. **Organize your anime**: Keep episodes in separate folders per series for better caching
2. **Use consistent naming**: Standard naming helps episode detection
3. **Enable notifications**: Helps track download progress
4. **Check cache**: Subtitles are reused from cache, saving bandwidth
5. **Manual lookup**: If auto-detection fails, manual lookup is very accurate

## Windows-Specific Notes

- Use forward slashes in paths: `C:/temp/subloader`
- Or escape backslashes: `C:\\temp\\subloader`
- Cache directory default: `C:/temp/subloader`
- Config location: `%APPDATA%/mpv/script-opts/mpv-subversive.conf`

## Performance

- First lookup: ~2-5 seconds (AniList + Jimaku API)
- Cached lookup: <1 second
- Archive extraction: 1-10 seconds depending on size
- Subtitle download: 1-5 seconds per file
