#!/bin/bash

CONFFILE=/etc/backup/backup.conf


# getting config parameters
source $CONFFILE
if [ -s "$HOME/.backup" ]; then
    source $HOME/.backup
fi


# getting binary paths
awk=`which awk`
cat=`which cat`
date=`which date`
grep=`which grep`
hostname=`which hostname`
install=`which install`
rm=`which rm`
rsync=`which rsync`
sed=`which sed`
sort=`which sort`
tar=`which tar`
TAR_ATTR='cvzf'


# setting variables
TIMESTAMP=$($date "+%Y/%m/%d/%H:%M:%S")

HOSTNAME=`$hostname`
HIST="$DESTINATION/$HOSTNAME/history/$TIMESTAMP"
BACKUP="$DESTINATION/$HOSTNAME/backup/"
LOGS="$DESTINATION/$HOSTNAME/log/$TIMESTAMP"

TMP="/tmp/backup"

DATEFILE="$DESTINATION/timestamp.$HOSTNAME"
NOW=`$date +%Y%m%d`
OLDDATE=`$cat "$DATEFILE"`

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
$install --directory "$HIST"
$install --directory "$BACKUP"
$install --directory "$LOGS"
$install --directory "$TMP"
$install --directory "$DESTINATION"


# start to work
## put what have moved in a temporary file
for SOURCE in $SOURCES; do
    $rsync --dry-run --itemize-changes --out-format="%i|%n|" --relative \
        --recursive --update --delete --perms --owner --group --times --links \
        --safe-links --super --one-file-system --devices ${EXCLUDE} \
	"$SOURCE" "$BACKUP" | sed '/^ *$/d' >> "$LOGS/dryrun"
done

## get all files
$grep "^.f" "$LOGS/dryrun" >> "$LOGS/onlyfiles"

## get new files
$grep "^.f+++++++++" "$LOGS/onlyfiles" \
    | $awk -F '|' '{print $2 }' | sed 's@^/@@' >> "$LOGS/created"

## get created directories
$grep "^cd" "$LOGS/dryrun" | $awk -F '|' '{print $2 }' \
    | $sed -e 's@^/@@' -e 's@/$@@' >> "$LOGS/created"

## get modified files
$grep --invert-match "^.f+++++++++" "$LOGS/onlyfiles" \
    | $awk -F '|' '{print $2 }' | sed 's@^/@@' >> "$LOGS/changed"

## get modified directories
$grep "^\.d" "$LOGS/dryrun" | $awk -F '|' '{print $2 }' \
    | $sed -e 's@^/@@' -e 's@/$@@' >> "$LOGS/changed"

## get deleted files and directories
$grep "^*deleting" "$LOGS/dryrun" \
    | $awk -F '|' '{print $2 }' >> "$LOGS/deleted"

## make a list of files and directories to move to history (deleted and updated one)
$cat "$LOGS/deleted" > "$TMP/tmp.rsync.list"
$cat "$LOGS/changed" >> "$TMP/tmp.rsync.list"
$sort --output="$TMP/rsync.list" --unique "$TMP/tmp.rsync.list"

## put files in history
if [ -s "$TMP/rsync.list" ]; then
    $rsync --relative --update --perms --owner --group --times --links --super \
        --files-from="$TMP/rsync.list" "$BACKUP" "$HIST"
fi

## get files from source
for SOURCE in $SOURCES; do
    $rsync --relative --recursive --update --delete --perms --owner --group --times \
        --links --safe-links --super --one-file-system --devices ${EXCLUDE} \
	"$SOURCE" "$BACKUP"
done

## if history is empty, remove it
if [ `du -sh "$HIST" | awk '{print $1}'` == '4,0K' ]; then
    $rm -fr "$HIST"
## if no files in history, remove it
elif [ `find "$HIST" -type f | wc -l` -eq 0 ]; then
    $rm -fr "$HIST"
## otherwise tar it
else
    $tar $TAR_ATTR "${HIST}.tgz" "$HIST" > "${HIST}.log"
    $rm -fr "$HIST"
fi

## if logs are empty, remove them
if [ `du -sh "$LOGS" | awk '{print $1}'` == '4,0K' ]; then
    $rm -fr "$LOGS"
fi
