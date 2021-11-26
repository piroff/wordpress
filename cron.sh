#!/bin/bash

USER='DB_USER'
PASS='DB_PASS'
DBNAME='DB_NAME'
DBHOST='DB_ADDR'
DOW=$(date +%A)


# get size func

function get_size()
{
echo Get $DBNAME tables size
mysql -u $USER --password=$PASS -h $DBHOST $DBNAME -Bse \
"SELECT
  TABLE_NAME AS \`Table\`,
  ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 ) AS \`Size (KB)\`
FROM
  information_schema.TABLES
WHERE
  TABLE_SCHEMA = \"$DBNAME\"
ORDER BY
  1,2
DESC;"
}


# Optimize

function optimize()
{
mysqlcheck -o -u $USER --password=$PASS -h $DBHOST $DBNAME
}


get_size > /tmp/$DOW-size-before-optimize.log
optimize > /tmp/$DOW-optimize.log
get_size > /tmp/$DOW-size-after-optimize.log

echo Done!
