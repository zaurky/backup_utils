#!/bin/bash

CONFFILE=/etc/backup/backup.conf


# getting config parameters
source $CONFFILE
if [ -s "$HOME/.backup" ]; then
    source $HOME/.backup
fi


# getting binary paths
CAT=`which cat`
SED=`which sed`
DATE=`which date`
AWK=`which awk`
RSYNC=`which rsync`
RM=`rm`
GREP=`grep`
SORT=`sort`
TAR=`which tar`
TAR_ATTR='cvzf'


# setting variables
TIMESTAMP=$($DATE "+%Y/%m/%d/%H:%M:%S")

HIST="$DESTINATION/$HOSTNAME/history/$TIMESTAMP"
BACKUP="$DESTINATION/$HOSTNAME/backup/"
LOGS="$DESTINATION/$HOSTNAME/log/$TIMESTAMP"

TMP="/tmp/backup"

DATEFILE="$DATEFILE.$HOSTNAME"
NOW=`$DATE +%Y%m%d`
OLDDATE=`$CAT "$DATEFILE"`

EXCLUDEFILE="/etc/backup/exclude"
EXCLUDE=''
if [ -s "$EXCLUDEFILE" ]; then
    EXCLUDE="--exclude-from=$EXCLUDEFILE"
fi


# checking if backup is needed/wanted
if [ "x`mount | grep $DESTINATION`" == "x" ]; then
    echo "backup disk is not here"
    exit
fi

if [ "x$OLDDATE" == "x$NOW" ]; then
    echo "run the same day"
    exit
fi

echo $NOW > "$DATEFILE"


# creating dirs
install --directory "$HIST"
install --directory "$BACKUP"
install --directory "$LOGS"
install --directory "$TMP"
install --directory "$DESTINATION"


# start to work
for SOURCE in $FROM; do
    $RSYNC --dry-run --itemize-changes --out-format="%i|%n|" --relative \
        --recursive --update --delete --perms --owner --group --times --links \
        --safe-links --super --one-file-system --devices ${EXCLUDE} \
	"$SOURCE" "$BACKUP" | sed '/^ *$/d' >> "$LOGS/dryrun"
done

$GREP "^.f" "$LOGS/dryrun" >> "$LOGS/onlyfiles"

$GREP "^.f+++++++++" "$LOGS/onlyfiles" \
    | $AWK -F '|' '{print $2 }' | sed 's@^/@@' >> "$LOGS/created"

$GREP --invert-match "^.f+++++++++" "$LOGS/onlyfiles" \
    | $AWK -F '|' '{print $2 }' | sed 's@^/@@' >> "$LOGS/changed"

$GREP "^\.d" "$LOGS/dryrun" | $AWK -F '|' '{print $2 }' \
    | $SED -e 's@^/@@' -e 's@/$@@' >> "$LOGS/changed"

$GREP "^cd" "$LOGS/dryrun" | $AWK -F '|' '{print $2 }' \
    | $SED -e 's@^/@@' -e 's@/$@@' >> "$LOGS/created"

$GREP "^*deleting" "$LOGS/dryrun" \
    | $AWK -F '|' '{print $2 }' >> "$LOGS/deleted"

$CAT "$LOGS/deleted" > "$TMP/tmp.rsync.list"
$CAT "$LOGS/changed" >> "$TMP/tmp.rsync.list"
$SORT --output="$TMP/rsync.list" --unique "$TMP/tmp.rsync.list"

if [ -s "$TMP/rsync.list" ]; then
    $RSYNC --relative --update --perms --owner --group --times --links --super \
        --files-from="$TMP/rsync.list" "$backup" "$HIST"
fi

for SOURCE in $FROM; do
    $RSYNC --relative --recursive --update --delete --perms --owner --group --times \
        --links --safe-links --super --one-file-system --devices ${EXCLUDE} \
	"$SOURCE" "$BACKUP"
done

if [ `du -sh "$HIST" | awk '{print $1}'` == '4,0K' ]; then
    rm -fr "$HIST"
elif [ `find "$HIST" -type f | wc -l` -eq 0 ]; then
    rm -fr "$HIST"
else
    $TAR $TAR_ATTR "${HIST}.tgz" "$HIST" > "${HIST}.log"
    rm -fr "$HIST"
fi

if [ `du -sh "$LOGS" | awk '{print $1}'` == '4,0K' ]; then
    rm -fr "$LOGS"
fi
