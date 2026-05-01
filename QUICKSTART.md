# mpv-subversive - Quick Reference

## What Was Fixed

### Critical Issues Resolved
1. ✅ **Subtitles not loading** - Fixed incorrect MPV command syntax
2. ✅ **Episode 77 not detected** - Improved filename parsing with 10+ patterns
3. ✅ **Poor error messages** - Added comprehensive error handling
4. ✅ **No user feedback** - Added progress indicators and notifications

## Quick Setup (3 Steps)

1. **Get API Token**
   - Visit: https://jimaku.cc/account
   - Copy your API token

2. **Create Config File**
   - Windows: `%APPDATA%\mpv\script-opts\mpv-subversive.conf`
   - Linux: `~/.config/mpv/script-opts/mpv-subversive.conf`
   
   ```ini
   API_TOKEN=your_token_here
   show_notifications=yes
   cache_directory=C:/temp/subloader
   ```

3. **Test It**
   - Open a video in MPV
   - Press `q` to open subtitle menu
   - Select a subtitle with Enter

## Usage

### Basic
- `q` - Open subtitle browser
- `↑`/`↓` or `j`/`k` - Navigate
- `Enter` or `l` - Load subtitle
- `ESC` or `n` - Close menu

### Advanced
- First menu option: Manual show lookup
- Second menu option: Change episode number
- Third menu option: Toggle show all files

## Troubleshooting

### No subtitles appear
1. Check console for error messages (press `` ` `` in MPV)
2. Verify API token is correct
3. Check episode number was detected: look for `episode number: 'XX'` in console
4. Try manual lookup if auto-detection fails

### Episode not detected
- Check console for: `episode number: '-1'` (means failed)
- Use "Modify episode number" option in menu
- Check filename follows common patterns

### Download fails
- Check internet connection
- Verify API token is valid
- Check cache directory is writable
- Look for error messages in console

### Run Diagnostics
Load the diagnostic script in MPV console:
```
script-message-to mpv_subversive_diag run
```

## New Features You Should Try

1. **Auto-Load** (optional)
   ```ini
   auto_load_subs=yes
   ```
   Automatically loads matching subtitles when you open a video

2. **Better Notifications**
   ```ini
   show_notifications=yes
   ```
   Shows progress and status messages

3. **Download Retry**
   ```ini
   download_retry_count=3
   ```
   Automatically retries failed downloads

## Files Created

- `USAGE.md` - Comprehensive usage guide
- `IMPROVEMENTS.md` - Detailed list of all improvements
- `mpv-subversive.conf.example` - Configuration template
- `diagnostic.lua` - Troubleshooting tool

## What's Better Now

### User Experience
- ✅ Real-time download progress (0-100%)
- ✅ Clear status indicators: [MATCH], [DOWNLOADING], [FAILED]
- ✅ Matching episodes highlighted and sorted first
- ✅ Better error messages
- ✅ Configurable notifications

### Reliability
- ✅ Handles network failures gracefully
- ✅ Automatic retry on download failures
- ✅ Better API error handling
- ✅ No crashes on errors

### Compatibility
- ✅ Works on Windows and Linux
- ✅ Handles various filename formats
- ✅ Supports multiple episode numbering styles
- ✅ Better path handling

### Performance
- ✅ Caches downloads for reuse
- ✅ Faster episode matching
- ✅ Efficient archive extraction
- ✅ Smart sorting

## Configuration Options

| Option | Default | What It Does |
|--------|---------|--------------|
| `API_TOKEN` | (empty) | **Required** - Your Jimaku API key |
| `show_notifications` | yes | Show OSD messages |
| `auto_load_subs` | no | Auto-load matching subs |
| `cache_directory` | /tmp/subloader | Where to cache downloads |
| `chosen_sub_dir` | ./subs | Where to save selected subs |
| `download_retry_count` | 3 | Retry failed downloads |

## Common Patterns Detected

The script now detects these filename patterns:
- `Show Name 077.mkv` → Episode 77 ✅
- `Show Name - 01.mkv` → Episode 1 ✅
- `Show Name S01E05.mkv` → Episode 5 ✅
- `[Group] Show Name EP12 [1080p].mkv` → Episode 12 ✅
- `Show.Name.E03.720p.mkv` → Episode 3 ✅

## Getting Help

1. Check console messages (press `` ` `` in MPV)
2. Read `USAGE.md` for detailed guide
3. Run diagnostic tool: `script-message-to mpv_subversive_diag run`
4. Check `IMPROVEMENTS.md` for technical details

## Tips

1. **Keep episodes in folders** - Better caching per series
2. **Use standard naming** - Helps episode detection
3. **Enable notifications** - See what's happening
4. **Check console** - Detailed info for debugging
5. **Manual lookup works** - If auto-detection fails

## Next Steps

1. Configure your API token
2. Test with a known anime
3. Check console for any errors
4. Enable auto-load if you like it
5. Enjoy your subtitles! 🎉

---

**Need more help?** Check the detailed guides:
- `USAGE.md` - Complete usage documentation
- `IMPROVEMENTS.md` - Technical details of changes
- `mpv-subversive.conf.example` - All configuration options
