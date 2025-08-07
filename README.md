# anilist-tui

**anilist-tui** is a terminal-based TUI written in shell script for managing your [AniList](https://anilist.co/) list from your Terminal.

---

## Requirements

- `curl`
- `jq` 
- `fzf` 
- `awk` 

---

## Installation Requirements

#### Ubuntu/ Debian
```Bash
sudo apt update
sudo apt install -y bash curl jq fzf awk
```
#### Arch Linux
```Bash
sudo pacman -Syu --needed bash curl jq fzf gawk
```
#### MacOS (with [Homebrew](https://brew.sh/))
```Bash
brew install bash curl jq fzf gawk
```
---

### Installation Linux/ MacOS

```bash
sudo curl -sL github.com/ThorFloTV/anilist-tui.sh -o /usr/local/bin/anilist-tui &&
sudo chmod +x /usr/local/bin/anilist-tui
