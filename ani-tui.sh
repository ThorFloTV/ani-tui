#!/bin/bash

TOKEN_FILE="$HOME/.anilist_token.json"

login() {
  clear
  echo "Go to this URL and authorize the app:"
  echo
  echo "https://anilist.co/api/v2/oauth/authorize?client_id=29126&response_type=token"
  echo

  read -rp "Paste your Full Token here: " access_token </dev/tty

  if [[ -z "$access_token" ]]; then
    echo "Error: Could not extract access token from the URL."
    exit 1
  fi

  jq -n --arg token "$access_token" '{"access_token": $token}' > "$TOKEN_FILE"

  echo "Logged in successfully!"
  read -rp "Press Enter to continue..." </dev/tty
}

load_token() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    login
  else
    access_token=$(jq -r '.access_token' < "$TOKEN_FILE")
    if [[ -z "$access_token" || "$access_token" == "null" ]]; then
      echo "Saved token is invalid or missing."
      login
    fi
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

while true; do
  action=$(printf '%s\n' "View details" "Update progress/status" "Back" | \
    fzf --layout=reverse --prompt="What do you want to do with this anime? ")

  case "$action" in
    "View details") show_anime_details "$id" ;;
    "Update progress/status") update_anime_entry "$id" ;;
    "Back"|"") break ;;
  esac
done

}

update_anime_entry() {
  clear
  local id="$1"

  while true; do
    choice=$(printf '%s\n' \
      "Set as Planned" \
      "Set as Watching" \
      "Set as Completed" \
      "Update Episode Progress" \
      "Edit Rating" \
      "Delete" \
      "⬅ Back" | fzf --layout=reverse --prompt="Choose update option: ")

    case "$choice" in
      "Set as Planned"|"Set as Watching"|"Set as Completed")
        case "$choice" in
          "Set as Planned") status="PLANNING" ;;
          "Set as Watching") status="CURRENT" ;;
          "Set as Completed") status="COMPLETED" ;;
        esac

        payload=$(jq -n --argjson mediaId "$id" --arg status "$status" '
        {
          query: "mutation ($mediaId: Int, $status: MediaListStatus) { SaveMediaListEntry(mediaId: $mediaId, status: $status) { id status } }",
          variables: {
            mediaId: $mediaId,
            status: $status
          }
        }')

        response=$(curl -s -H "Authorization: Bearer $access_token" \
          -X POST -H "Content-Type: application/json" \
          -d "$payload" https://graphql.anilist.co)

        errors=$(echo "$response" | jq '.errors')
        if [[ "$errors" == "null" ]]; then
          echo "Status updated to $status!"
        else
          echo "Failed to update status:"
          echo "$errors" | jq
        fi

        read -rp "Press Enter to return..." </dev/tty
        clear
        ;;
      
      "Update Episode Progress")
        query_info='query ($mediaId: Int) {
          Media(id: $mediaId) {
            episodes
            mediaListEntry {
              progress
            }
          }
        }'
        variables=$(jq -n --argjson mediaId "$id" '{mediaId: $mediaId}')
        payload=$(jq -n --arg query "$query_info" --argjson variables "$variables" '{query: $query, variables: $variables}')
        response=$(curl -s -H "Authorization: Bearer $access_token" -X POST -H "Content-Type: application/json" -d "$payload" https://graphql.anilist.co)

        total_eps=$(echo "$response" | jq -r '.data.Media.episodes // empty')
        current_progress=$(echo "$response" | jq -r '.data.Media.mediaListEntry.progress // 0')

        if [[ -n "$total_eps" && "$total_eps" != "null" ]]; then
          prompt="Enter episode progress ($current_progress / $total_eps): "
        else
          prompt="Enter episode progress (current: $current_progress): "
        fi

        read -rp "$prompt" episodes </dev/tty

        payload=$(jq -n --argjson mediaId "$id" --argjson progress "$episodes" '
        {
          query: "mutation ($mediaId: Int, $progress: Int) { SaveMediaListEntry(mediaId: $mediaId, progress: $progress) { id } }",
          variables: {
            mediaId: $mediaId,
            progress: $progress
          }
        }')

        curl -s -H "Authorization: Bearer $access_token" \
          -X POST -H "Content-Type: application/json" \
          -d "$payload" https://graphql.anilist.co > /dev/null

        echo "Episode progress updated!"
        read -rp "Press Enter to return..." </dev/tty
        clear
        ;;

      "Edit Rating")
        echo "Edit Rating feature coming soon!"
        read -rp "Press Enter..." </dev/tty
        clear
        ;;

      "Delete")
        confirm=$(printf "No\nYes" | fzf --layout=reverse --prompt="Are you sure you want to delete this entry? ")
        if [[ "$confirm" == "Yes" ]]; then
          read -r -d '' q << 'EOF'
query ($mediaId: Int) {
  Media(id: $mediaId) {
    mediaListEntry {
      id
    }
  }
}
EOF
          variables=$(jq -n --argjson mediaId "$id" '{mediaId: $mediaId}')
          payload=$(jq -n --arg query "$q" --argjson variables "$variables" '{query: $query, variables: $variables}')
          response=$(curl -s -H "Authorization: Bearer $access_token" -X POST -H "Content-Type: application/json" -d "$payload" https://graphql.anilist.co)
          entry_id=$(echo "$response" | jq -r '.data.Media.mediaListEntry.id // empty')
          if [[ -z "$entry_id" ]]; then
            echo "Could not find the list entry to delete."
            read -rp "Press Enter to return..." </dev/tty
            clear
            break
          fi
          delete_q='mutation ($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }'
          del_payload=$(jq -n --arg query "$delete_q" --argjson variables "{\"id\": $entry_id}" \
            '{query: $query, variables: $variables}')
          delete_resp=$(curl -s -H "Authorization: Bearer $access_token" -X POST -H "Content-Type: application/json" -d "$del_payload" https://graphql.anilist.co)
          errors=$(echo "$delete_resp" | jq '.errors')
          if [[ "$errors" == "null" ]]; then
            echo "Entry deleted successfully!"
          else
            echo "Deletion may have failed:"
            echo "$errors" | jq
          fi
          read -rp "Press Enter to return..." </dev/tty
          clear
          break
        else
          echo "Deletion cancelled."
          read -rp "Press Enter to return..." </dev/tty
          clear
        fi
        ;;

      "⬅ Back"|"" )
        break
        ;;
    esac
  done
}

set_anime_status() {
  local id="$1"
  local status="$2"

  payload=$(jq -n \
    --argjson mediaId "$id" \
    --arg status "$status" \
    '{
      query: "mutation ($mediaId: Int, $status: MediaListStatus) { SaveMediaListEntry(mediaId: $mediaId, status: $status) { id status } }",
      variables: { mediaId: $mediaId, status: $status }
    }')

  response=$(curl -s -H "Authorization: Bearer $access_token" \
    -X POST -H "Content-Type: application/json" \
    -d "$payload" https://graphql.anilist.co)

  if echo "$response" | jq -e '.errors' &>/dev/null; then
    echo "Failed to update status."
    echo "$response" | jq
  else
    echo "Status updated to: $status"
  fi

  read -rp "Press Enter to continue..." </dev/tty
}

update_anime_progress() {
  local id="$1"
  local max_eps="$2"

  read -rp "Enter new episode progress (0-${max_eps}): " progress </dev/tty

  if [[ -z "$progress" || ! "$progress" =~ ^[0-9]+$ ]]; then
    echo "Invalid input. Must be a number."
    read -rp "Press Enter to return..." </dev/tty
    return
  fi

    --argjson mediaId "$id" \
  payload=$(jq -n \
    --argjson progress "$progress" \
    '{
      query: "mutation ($mediaId: Int, $progress: Int) { SaveMediaListEntry(mediaId: $mediaId, progress: $progress) { id progress } }",
      variables: { mediaId: $mediaId, progress: $progress }
    }')

  response=$(curl -s -H "Authorization: Bearer $access_token" \
    -X POST -H "Content-Type: application/json" \
    -d "$payload" https://graphql.anilist.co)

  if echo "$response" | jq -e '.errors' &>/dev/null; then
    echo "Failed to update progress."
    echo "$response" | jq
  else
    echo "Progress updated to: $progress"
  fi

  read -rp "Press Enter to continue..." </dev/tty
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

while true; do
  action=$(printf '%s\n' "View details" "Update progress/status" "Back" | \
    fzf --layout=reverse --prompt="What do you want to do with this anime? ")

  case "$action" in
    "View details") show_anime_details "$id" ;;
    "Update progress/status") update_anime_entry "$id" ;;
    "Back"|"") break ;;
  esac
done

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
