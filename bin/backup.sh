#!/bin/bash

source /etc/backup.conf
source $HOME/.backup

if [ "x`mount | grep $DESTINATION`" == "x" ]; then
    echo "backup disk is not here"
    exit
fi

DATEFILE="$DATEFILE.$HOSTNAME"
DATE=`date +%Y%m%d`
OLDDATE=`cat "$DATEFILE"`

if [ "x$OLDDATE" == "x$DATE" ]; then
    echo "run the same day"
    exit
fi

echo $DATE > "$DATEFILE"

dest="$DESTINATION"
mkdir -p "$dest"

EXCLUDE=''
if [ -s "$HOME/.backup.exclude" ]; then
    EXCLUDE="--exclude-from=$HOME/.backup.exclude"
fi

timestamp=$(date "+%Y/%m/%d/%H:%M:%S")

hist="$dest/$HOSTNAME/history/$timestamp"
backup="$dest/$HOSTNAME/backup/"
logs="$dest/$HOSTNAME/log/$timestamp"

install --directory "$hist"
install --directory "$backup"
install --directory "$logs"

for from in $FROM; do
    rsync --dry-run --itemize-changes --out-format="%i|%n|" --relative \
        --recursive --update --delete --perms --owner --group --times --links \
        --safe-links --super --one-file-system --devices ${EXCLUDE} \
	"$from" "$backup" | sed '/^ *$/d' >> "$logs/dryrun"
done

grep "^.f" "$logs/dryrun" >> "$logs/onlyfiles"

grep "^.f+++++++++" "$logs/onlyfiles" \
    | awk -F '|' '{print $2 }' | sed 's@^/@@' >> "$logs/created"

grep --invert-match "^.f+++++++++" "$logs/onlyfiles" \
    | awk -F '|' '{print $2 }' | sed 's@^/@@' >> "$logs/changed"

grep "^\.d" "$logs/dryrun" | awk -F '|' '{print $2 }' \
    | sed -e 's@^/@@' -e 's@/$@@' >> "$logs/changed"

grep "^cd" "$logs/dryrun" | awk -F '|' '{print $2 }' \
    | sed -e 's@^/@@' -e 's@/$@@' >> "$logs/created"

grep "^*deleting" "$logs/dryrun" \
    | awk -F '|' '{print $2 }' >> "$logs/deleted"

cat "$logs/deleted" > /tmp/tmp.rsync.list
cat "$logs/changed" >> /tmp/tmp.rsync.list
sort --output=/tmp/rsync.list --unique /tmp/tmp.rsync.list

if [ -s "/tmp/rsync.list" ]; then
    rsync --relative --update --perms --owner --group --times --links --super \
        --files-from=/tmp/rsync.list "$backup" "$hist"
fi

for from in $FROM; do
    rsync --relative --recursive --update --delete --perms --owner --group --times \
        --links --safe-links --super --one-file-system --devices ${EXCLUDE} \
	"$from" "$backup"
done

if [ `du -sh "$hist" | awk '{print $1}'` == '4,0K' ]; then
    rm -fr "$hist"
elif [ `find "$hist" -type f | wc -l` -eq 0 ]; then
    rm -fr "$hist"
else
    tar cvzf "${hist}.tgz" "$hist" > "${hist}.log"
    rm -fr "$hist"
fi

if [ `du -sh "$logs" | awk '{print $1}'` == '4,0K' ]; then
    rm -fr "$logs"
fi
