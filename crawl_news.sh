#!/bin/bash

set -eo pipefail

OLD_FEED=./current.txt
CURRENT_FEED=$(mktemp -p /tmp crawl_feed.XXX)
BOT_TOKEN=${BOT_TOKEN:=""}
CHANNEL_ID=${CHANNEL_ID:="@dcss_news"}
URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

SHORT_COMMITS=$(mktemp -p /tmp crawl.XXXX)

wget https://github.com/crawl/crawl/commits/master.atom -O /tmp/master.atom

xmlstarlet sel -N x=http://www.w3.org/2005/Atom -t -m "//x:entry" -v "x:content"  -v "x:link/@href" -n -o "----" -n /tmp/master.atom | sed -e 's/&amp;\|&#38;/\&/g' -e 's/&lt;\|&#60;/</g' -e 's/&gt;\|&#62;/>/g' -e 's/&quot;\|&#34;/"/g' -e "s/&apos;\|&#39;/'/g" -e 's/&nbsp;|&#160;/ /g' | grep -v '^$' | sed 's/^[ \t]*//' > $CURRENT_FEED

function join_by { local IFS="$1"; shift; echo "$*"; }

push_news() {
    DATA=$(echo "$1" | grep -v "^\s*$")
    IFS=$'\n' read -rd '' HEADER LINK <<<"$DATA"

    if [[ $(echo "$DATA" | wc -l ) == 2 ]]
    then
        # TODO: normalize the string(converting html entities)
        echo "<a href='${LINK}'>${HEADER}</a>" >> $SHORT_COMMITS
    else
        curl -s -X POST "$URL" -d chat_id=$CHANNEL_ID -d parse_mode="HTML" -d text="<b>${HEADER}</b>"$'\n'"${LINK}"
    fi
}

export -f push_news
export SHORT_COMMITS URL CHANNEL_ID

if [ -f "$OLD_FEED" ]
then
    diff $OLD_FEED $CURRENT_FEED --changed-group-format="%>" --unchanged-group-format="" | tac -s $'\n----' |   sed -e 's/----/\x0/' -e 's/<[^>]\+>//g' | xargs -0 -I{} -- bash -c 'push_news "$@"' _ {}
else
    tac -s $'\n----' $CURRENT_FEED | sed -e 's/----/\x0/' -e 's/<[^>]\+>//g' | xargs -0 -I{} -- bash -c 'push_news "$@"' _ {}
fi

if [ -s "$SHORT_COMMITS" ]; then
    mapfile LINKS < $SHORT_COMMITS
    curl -s -X POST $URL -d chat_id=$CHANNEL_ID -d parse_mode="HTML" -d text="<b>minor changes:</b>"$'\n'"$(join_by $'\n' "${LINKS[@]}")"
fi

mv "$CURRENT_FEED" "$OLD_FEED"
