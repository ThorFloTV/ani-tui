#!/bin/bash

CLIENT_ID="29126"
CLIENT_SECRET="WyeuhEO8OsS6VnvpHEY34dRoQo2hftn8ar3Rs2mo"
REDIRECT_URI="https://anilist.co/api/v2/oauth/pin"
TOKEN_FILE="$HOME/.anilist_token.json"

login() {
clear
echo "Go to this URL and authorize the app:"
echo "https://anilist.co/api/v2/oauth/authorize?client_id=$CLIENT_ID&response_type=code&redirect_uri=$REDIRECT_URI"
read -rp "Paste the authorization code here: " code </dev/tty

token_response=$(curl -s -X POST "https://anilist.co/api/v2/oauth/token" \
-d grant_type=authorization_code \
-d client_id="$CLIENT_ID" \
-d client_secret="$CLIENT_SECRET" \
-d code="$code" \
-d redirect_uri="$REDIRECT_URI")

echo "$token_response" > "$TOKEN_FILE"

access_token=$(echo "$token_response" | jq -r '.access_token')

if [[ "$access_token" == "null" || -z "$access_token" ]]; then
echo "Login failed."
exit 1
fi

echo "Logged in successfully!"
read -rp "Press Enter to continue..." </dev/tty
}

load_token() {
if [[ ! -f "$TOKEN_FILE" ]]; then
login
else
access_token=$(jq -r '.access_token' < "$TOKEN_FILE")
refresh_token=$(jq -r '.refresh_token' < "$TOKEN_FILE")
fi
}

get_viewer_id() {
response=$(curl -s -H "Authorization: Bearer $access_token" -X POST -H "Content-Type: application/json" \
-d '{"query":"query { Viewer { id } }"}' https://graphql.anilist.co)
echo "$response" | jq -r '.data.Viewer.id'
}

format_score() {
local score=$1
if [[ "$score" == "null" || "$score" == "N/A" || -z "$score" ]]; then
echo "N/A"
else
awk -v s="$score" 'BEGIN {printf "%.0f", s/10}'
fi
}

search_anime() {
local search="$1"

read -r -d '' query <<EOF
query (\$search: String) {
Page(perPage: 20) {
media(search: \$search, type: ANIME) {
id
title {
romaji
english
}
episodes
status
averageScore
mediaListEntry {
status
}
}
}
}
EOF

variables=$(jq -n --arg search "$search" '{search: $search}')
payload=$(jq -n --arg query "$query" --argjson variables "$variables" '{query: $query, variables: $variables}')

response=$(curl -s -H "Authorization: Bearer $access_token" -X POST -H "Content-Type: application/json" -d "$payload" https://graphql.anilist.co)

echo "$response" | jq -r '.data.Page.media[] | @base64' | while read -r line; do
_jq() {
echo "$line" | base64 --decode | jq -r "$1"
}

id=$(_jq '.id')
english=$(_jq '.title.english // empty')
romaji=$(_jq '.title.romaji')
title="${english:-$romaji}"
episodes=$(_jq '.episodes')
[[ "$episodes" == "0" ]] && episodes="?"
status=$(_jq '.status')
avg_score=$(_jq '.averageScore // "N/A"')
my_status=$(_jq '.mediaListEntry.status // "N/A"')

if (( ${#title} > 50 )); then
title="${title:0:47}..."
fi

printf "%s\t%-50s %8s %12s %12s\n" "$id" "$title" "0/$episodes" "$status" "$my_status"
done
}

menu() {
while true; do
clear
option=$(printf '%s\n' \
"Search for anime" \
"View currently watching anime" \
"View completed anime" \
"View planned anime" \
"Exit" | fzf --layout=reverse --prompt="Select option: ")

case "$option" in
"Search for anime") search_menu ;;
"View currently watching anime") list_menu "CURRENT" ;;
"View completed anime") list_menu "COMPLETED" ;;
"View planned anime") list_menu "PLANNING" ;;
"Exit")
clear
show_exit_message
exit 0
;;
"") clear; show_exit_message; exit 0 ;;
*) echo "Invalid option." ;;
esac
done
}

search_menu() {
clear
search=$(printf "" | fzf --layout=reverse --print-query --prompt="Type anime name and press Enter: " --height=10 --border | head -1)

if [[ -z "$search" ]]; then
echo "No search term entered."
read -rp "Press Enter to return to menu..." </dev/tty
return
fi

results=$(search_anime "$search")

if [[ -z "$results" ]]; then
echo "No results found."
read -rp "Press Enter to return to menu..." </dev/tty
return
fi

header=$(printf "%-50s %8s %12s %12s\n" "Title" "Episodes" "Status" "MyStatus")

selected=$( (echo -e "$header" && echo "$results") | fzf --layout=reverse --delimiter=$'\t' --with-nth=2.. --header-lines=1 --prompt="Search results: ")
if [[ -z "$selected" ]]; then
echo "No selection."
read -rp "Press Enter to return to menu..." </dev/tty
return
fi

id=$(echo "$selected" | cut -f1)
show_anime_details "$id"
}

list_menu() {
clear
local status=$1
user_id=$(get_viewer_id)

read -r -d '' query <<EOF
query (\$userId: Int, \$status: MediaListStatus) {
MediaListCollection(userId: \$userId, status: \$status, type: ANIME) {
lists {
entries {
media {
id
title {
romaji
english
}
episodes
status
averageScore
}
progress
}
}
}
}
EOF

variables=$(jq -n --argjson userId "$user_id" --arg status "$status" '{userId: $userId, status: $status}')
payload=$(jq -n --arg query "$query" --argjson variables "$variables" '{query: $query, variables: $variables}')
json=$(curl -s -H "Authorization: Bearer $access_token" -X POST -H "Content-Type: application/json" -d "$payload" https://graphql.anilist.co)

entries=$(echo "$json" | jq -r '.data.MediaListCollection.lists[]?.entries[]? | @base64')
if [[ -z "$entries" ]]; then
echo "No anime found for status $status."
read -rp "Press Enter to return to menu..." </dev/tty
return
fi

header=$(printf "%-50s %8s %12s %8s\n" "Title" "Episodes" "Status" "AvgScore")

formatted_entries=$(echo "$entries" | while read -r line; do
_jq() {
echo "$line" | base64 --decode | jq -r "$1"
}

id=$(_jq '.media.id')
english=$(_jq '.media.title.english // empty')
romaji=$(_jq '.media.title.romaji')
title="${english:-$romaji}"
progress=$(_jq '.progress // 0')
episodes=$(_jq '.media.episodes // 0')
[[ "$episodes" == "0" ]] && episodes="?"
status_line=$(_jq '.media.status')
avg_score=$(format_score "$(_jq '.media.averageScore // "N/A"')")

if (( ${#title} > 50 )); then
title="${title:0:47}..."
fi

printf "%s\t%-50s %8s %12s %8s\n" "$id" "$title" "$progress/$episodes" "$status_line" "$avg_score"
done)

selected=$( (echo -e "$header" && echo "$formatted_entries") | fzf --layout=reverse --delimiter=$'\t' --with-nth=2.. --header-lines=1 --prompt="$status anime: ")
if [[ -z "$selected" ]]; then
echo "No selection."
read -rp "Press Enter to return to menu..." </dev/tty
return
fi
id=$(echo "$selected" | cut -f1)
show_anime_details "$id"
}

show_anime_details() {
clear
local id=$1

read -r -d '' query <<EOF
query (\$id: Int) {
Media(id: \$id, type: ANIME) {
id
title {
romaji
english
native
}
episodes
status
description(asHtml: false)
genres
averageScore
siteUrl
}
}
EOF

variables=$(jq -n --argjson id "$id" '{id: $id}')
payload=$(jq -n --arg query "$query" --argjson variables "$variables" '{query: $query, variables: $variables}')
response=$(curl -s -H "Authorization: Bearer $access_token" -X POST -H "Content-Type: application/json" -d "$payload" https://graphql.anilist.co)

title_romaji=$(echo "$response" | jq -r '.data.Media.title.romaji')
title_english=$(echo "$response" | jq -r '.data.Media.title.english // empty')
episodes=$(echo "$response" | jq -r '.data.Media.episodes')
status=$(echo "$response" | jq -r '.data.Media.status')
description=$(echo "$response" | jq -r '.data.Media.description' | sed 's/<[^>]*>//g' | fold -s -w 80)
genres=$(echo "$response" | jq -r '.data.Media.genres | join(", ")')
score=$(echo "$response" | jq -r '.data.Media.averageScore')
url=$(echo "$response" | jq -r '.data.Media.siteUrl')

echo ""
echo "Title: $title_romaji"
[[ -n "$title_english" ]] && echo "English Title: $title_english"
echo "Episodes: $episodes"
echo "Status: $status"
echo "Genres: $genres"
echo "Score: $score"
echo ""
echo "Description:"
echo "$description"
echo ""
echo "URL: $url"
echo ""
read -rp "Press Enter to return..." </dev/tty
}

show_exit_message() {
clear
if command -v fastfetch &>/dev/null; then
fastfetch
elif command -v neofetch &>/dev/null; then
neofetch
fi
}

main() {
load_token
menu
}

main
