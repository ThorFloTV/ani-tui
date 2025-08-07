# ani-tui

**ani-tui** is a terminal-based TUI written in shell script for managing your [AniList](https://anilist.co/) list from your Terminal.

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
sudo pacman -Sy --needed bash curl jq fzf gawk
```
---

### Installation

```bash
sudo curl -sL github.com/ThorFloTV/ani-tui/raw/main/ani-tui.sh -o /usr/local/bin/ani-tui &&
sudo chmod +x /usr/local/bin/ani-tui
```
---
# Credits
- Anilist API: https://anilist.gitbook.io/anilist-apiv2-docs
