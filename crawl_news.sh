#!/bin/bash

set -xe

OLD_FEED=./current.json
CURRENT_FEED=$(mktemp -p /tmp crawl_feed.XXX)
BOT_TOKEN=${BOT_TOKEN:=""}
CHANNEL_ID=${CHANNEL_ID:="@dcss_news"}
URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

SHORT_COMMITS=$(mktemp -p /tmp crawl.XXXX)

curl -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/crawl/crawl/commits?per_page=100" -o $CURRENT_FEED


# TODO: handle the case where one of message get lost(due to connection error or something)
push_news() {
    DATA=$(echo "$1" | grep -v "^\s*$")

    if [[ $(echo "$DATA" | wc -l ) == 1 ]]
    then
        # TODO: normalize the string(converting html entities like &) and causes to some message be trimmed
        echo "$DATA" >> $SHORT_COMMITS
    else
        curl -s -X POST "$URL" -d chat_id=$CHANNEL_ID -d parse_mode="HTML" -d text="$DATA"
        sleep 5
    fi
}

export -f push_news
export SHORT_COMMITS URL CHANNEL_ID

if [ -f "$OLD_FEED" ]
then
    jq -s -r '(.[0] - .[1])[] | ( (.commit.message / "\n\n") as $msg | if ( $msg | length ) > 1 then "<b>"+ $msg[0] + "</b>", (  $msg[1:][] | gsub("\n"; "") ), .html_url else "<a href=\"" + .html_url + "\">" + $msg[0] + "</a>" end), "----"' "$CURRENT_FEED" "$OLD_FEED" | tac -s '----' | sed 's/----/\x0/' | xargs -0 -I{} -- bash -c 'push_news "$@"' _ {}
else
    jq -r '.[] | ( (.commit.message / "\n\n") as $msg | if ( $msg | length ) > 1 then "<b>"+ $msg[0] + "</b>", (  $msg[1:][] | gsub("\n"; "") ), .html_url else "<a href=\"" + .html_url + "\">" + $msg[0] + "</a>" end), "----"' "$CURRENT_FEED" | tac -s '----' | sed 's/----/\x0/' | xargs -0 -I{} -- bash -c 'push_news "$@"' _ {}
fi

[ -s "$SHORT_COMMITS" ] && curl -s -X POST $URL -d chat_id=$CHANNEL_ID -d parse_mode="HTML" -d text="<b>minor changes:</b>"$'\n'"$(cat $SHORT_COMMITS)"

mv "$CURRENT_FEED" "$OLD_FEED"
