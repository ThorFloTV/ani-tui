# ani-tui

**ani-tui** is a terminal-based TUI written in shell script for managing your [AniList](https://anilist.co/) list from your Terminal.

---

## Requirements

- `curl`
- `jq` 
- `fzf` 
- `timg` 

---

## Installation Requirements

#### Ubuntu/ Debian
```Bash
sudo apt update
sudo apt install -y curl jq fzf timg
```
#### Arch Linux
```Bash
sudo pacman -Sy --needed curl jq fzf
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
