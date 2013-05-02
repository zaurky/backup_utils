#!/bin/bash

CONFFILE=/etc/backup/backup.conf


# getting config parameters
source $CONFFILE
if [ -s "$HOME/.backup" ]; then
    source $HOME/.backup
fi


# getting binary paths
AWK=`which awk`
CAT=`which cat`
DATE=`which date`
GREP=`grep`
INSTALL=`which install`
RM=`rm`
RSYNC=`which rsync`
SED=`which sed`
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
$INSTALL --directory "$HIST"
$INSTALL --directory "$BACKUP"
$INSTALL --directory "$LOGS"
$INSTALL --directory "$TMP"
$INSTALL --directory "$DESTINATION"


# start to work
## put what have moved in a temporary file
for SOURCE in $FROM; do
    $RSYNC --dry-run --itemize-changes --out-format="%i|%n|" --relative \
        --recursive --update --delete --perms --owner --group --times --links \
        --safe-links --super --one-file-system --devices ${EXCLUDE} \
	"$SOURCE" "$BACKUP" | sed '/^ *$/d' >> "$LOGS/dryrun"
done

## get all files
$GREP "^.f" "$LOGS/dryrun" >> "$LOGS/onlyfiles"

## get new files
$GREP "^.f+++++++++" "$LOGS/onlyfiles" \
    | $AWK -F '|' '{print $2 }' | sed 's@^/@@' >> "$LOGS/created"

## get created directories
$GREP "^cd" "$LOGS/dryrun" | $AWK -F '|' '{print $2 }' \
    | $SED -e 's@^/@@' -e 's@/$@@' >> "$LOGS/created"

## get modified files
$GREP --invert-match "^.f+++++++++" "$LOGS/onlyfiles" \
    | $AWK -F '|' '{print $2 }' | sed 's@^/@@' >> "$LOGS/changed"

## get modified directories
$GREP "^\.d" "$LOGS/dryrun" | $AWK -F '|' '{print $2 }' \
    | $SED -e 's@^/@@' -e 's@/$@@' >> "$LOGS/changed"

## get deleted files and directories
$GREP "^*deleting" "$LOGS/dryrun" \
    | $AWK -F '|' '{print $2 }' >> "$LOGS/deleted"

## make a list of files and directories to move to history (deleted and updated one)
$CAT "$LOGS/deleted" > "$TMP/tmp.rsync.list"
$CAT "$LOGS/changed" >> "$TMP/tmp.rsync.list"
$SORT --output="$TMP/rsync.list" --unique "$TMP/tmp.rsync.list"

## put files in history
if [ -s "$TMP/rsync.list" ]; then
    $RSYNC --relative --update --perms --owner --group --times --links --super \
        --files-from="$TMP/rsync.list" "$BACKUP" "$HIST"
fi

## get files from source
for SOURCE in $FROM; do
    $RSYNC --relative --recursive --update --delete --perms --owner --group --times \
        --links --safe-links --super --one-file-system --devices ${EXCLUDE} \
	"$SOURCE" "$BACKUP"
done

## if history is empty, remove it
if [ `du -sh "$HIST" | awk '{print $1}'` == '4,0K' ]; then
    $RM -fr "$HIST"
## if no files in history, remove it
elif [ `find "$HIST" -type f | wc -l` -eq 0 ]; then
    $RM -fr "$HIST"
## otherwise tar it
else
    $TAR $TAR_ATTR "${HIST}.tgz" "$HIST" > "${HIST}.log"
    $RM -fr "$HIST"
fi

## if logs are empty, remove them
if [ `du -sh "$LOGS" | awk '{print $1}'` == '4,0K' ]; then
    $RM -fr "$LOGS"
fi
