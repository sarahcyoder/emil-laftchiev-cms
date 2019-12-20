#!/bin/bash

# @file
# Local setup script for CHR.

usage() {
  echo "This script should be run on the host machine from the Drupal docroot."
  echo "$0 [dev|test|live] [with-files] [no-db]"
  echo ""
  echo "Files are not downloaded by default. You must add the 'with-files' option."
  echo "You can add 'no-db' to skip the database sync step."
}

# Ensure local settings file is present so Drush can start Drupal.
if [ ! -f sites/default/settings.local.php ]; then
    echo "Creating settings.local.php"
    cp sites/default/example.settings.local.php sites/default/settings.local.php
fi

if ! [ -x "$(command -v terminus)" ]; then
  echo 'Error: terminus is not installed.' >&2
  exit 1
fi

if ! [ -x "$(command -v curl)" ]; then
  echo 'Error: curl is not installed.' >&2
  exit 1
fi

if ! [ -x "$(command -v gunzip)" ]; then
  echo 'Error: gunzip is not installed.' >&2
  exit 1
fi

# Alias and default values.
TERMINUS_SOURCE="emil-laftchiev-cms"
SOURCE="@$TERMINUS_SOURCE"
ENV="live"
DB=1
FILES=0

while [ "$#" -ne 0 ]
do
  case "$1" in
    dev|test|live)
      ENV="$1"
      ;;

    no-db)
      DB=0
      ;;

    with-files)
      FILES=1
      ;;

    help|*)
      usage
      exit 1
      ;;
  esac
  shift
done

# Add temporary drush alias for SQL and file sync.
read -d '' ALIAS <<"EOF"
  <?php
  $local_repo = getcwd();
  $local_dumps = '/drush.dumps';
  $local_files = $local_repo . '/sites/default/files';
  $aliases['1'] = array(
    'root' => $local_repo,
    'path-aliases' => array(
      '%dump-dir' => $local_dumps,
      '%files' => $local_files,
    ),
  );
EOF
echo $ALIAS > ~/.drush/local.aliases.drushrc.php

REMOTE="${SOURCE}.${ENV}"
TERMINUS_REMOTE="${TERMINUS_SOURCE}.${ENV}"

if [ $DB -gt 0 ]; then
  echo "Downloading database from ${REMOTE}"
  # Not all pantheon sites can work with drush sql-sync. Evidently sites that
  # use more than one container cannot use it. To get around this, we will
  # use terminus to make a backup and pull the url of that backup. Then we will
  # can download it with curl and proceed.
  # See https://pantheon.io/docs/drush/

  terminus backup:create $TERMINUS_REMOTE --element=db
  DB=$(terminus backup:get $TERMINUS_REMOTE --element=db)
  curl -o db.sql.gz $DB
  gunzip < db.sql.gz | drush sql-cli
  rm db.sql.gz
fi

if [ $FILES -gt 0 ]; then
  echo "Downloading files from ${REMOTE}"
  drush -y rsync ${REMOTE}:%files/ @local.1:%files
fi

rm ~/.drush/local.aliases.drushrc.php


echo "Getting the site ready for local development..."
drush updb -y
drush cr all
drush uli

echo "Done!"
