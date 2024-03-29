#!/bin/bash


# Usage: sh import.sh site-name "Site Label" "databasename.sql"
# $1 = machine name of the site on Pantheon (unique, and the same as the folder that will be created)
# $2 = label of the site on Pantheon
# $3 = the name of the database file that is going to be imported


# Before running the script, you need:

# 1. A modified .gitignore file in the same directory as where you're running the script from

# 2. A composer-edits.php script file that edits the composer.json file to remove some of the pieces

# 3. You will also need to go the database in the cPanel backup file, open it, and 
# make sure that the import happens to a database named 'pantheon' rather than
# one that is named after the sql file. Lines to edit:
#
# -- Current Database: `pantheon`
# CREATE DATABASE /*!32312 IF NOT EXISTS*/ `pantheon` /*!40100 DEFAULT CHARACTER SET latin1 */;
# USE `pantheon`;

# 4. Renamed the cPanel backup folder to $1-backup. Example: site machine name is
# lmba, cPanel backup folder name: lmba-backup

# 5. Have both composer and terminus installed and working, as well as made the 
# authentication between your terminus command line and the Pantheon platform 
# @see https://pantheon.io/docs/terminus/install 

# 6. This script, .gitignore and composer-edits.php in the parent folder of where your projects will be 
# living. For me, this is User/work/3-projects/. A created project will live in 
# User/work/3-projects/lmba and this script lives in User/work/3-projects/import.sh. 

# 7. Replace your organization name and the e-mail address within the script 



export SITE_ID="$1"
export SITE_LABEL="$2"
export DB_FILE_NAME="$3"
export DIR="$PWD/$1"
export BACKUP_DIR="$1-backup"
export CURRENT_DIR=$PWD



# SET THE SITE UP IN PANTHEON ------------------------------------------------ #

# Create the site on Pantheon
terminus site:create $SITE_ID "$SITE_LABEL" empty --org "organization-name" --region eu

echo "Succesfully create a new site"

# Set the owner of the site to your org email
terminus site:team:add $SITE_ID "email-address@of.user"
terminus owner:set $SITE_ID "email-address@of.user"

# ---------------------------------------------------------------------------- #


# PREPARE LOCAL FILES -------------------------------------------------------- #

# Prepare the git repository by cloning the pantheon vesion of the Drupal composer project
git clone https://github.com/pantheon-systems/example-drops-8-composer.git $SITE_ID


# Move to the project directory - note that you couldn't move into the directory before it was created
cd $DIR


# Set the remote URL to the Pantheon Git URL
export PANTHEON_SITE_GIT_URL="$(terminus connection:info $SITE_ID.dev --field=git_url)"
git remote set-url origin $PANTHEON_SITE_GIT_URL


# Remove the automation directories
rm -r /scripts/github
rm -r /scripts/gitlab
rm -r /tests
rm -r /.circleci


# Run the php script to take pieces out of composer.json
/usr/bin/php composer-edits.php -- $SITE_ID


# Run composer update as well as install Drush
# We also require drupal/core:8.7.6 since 8.7.7 was not fixed at the time. You should
# change this as needed
composer require drupal/core:8.7.6
composer update
composer install


# We cannot install these yet because the installation hasn't been composerized yet
# composer require drush/drush
# composer require drupal/sendgrid_integration


# Enable git push mode on Pantheon's side
terminus connection:set $SITE_ID.dev git


# Replace the .gitignore file with the fixed version
cp $CURRENT_DIR/.gitignore ./

# ---------------------------------------------------------------------------- #


# PUSH CHANGES TO PANTHEON --------------------------------------------------- #

# Git commit
git add .
git commit -m "Drupal 8 and dependencies"
# You need to use --force to avoid unrelated histories error
echo yes | git push --force

# ---------------------------------------------------------------------------- #


# MERGE THE cPanel PROJECT IN AND PROCESS IT AS NEEDED ----------------------- #

cp -R $CURRENT_DIR/$BACKUP_DIR/homedir/public_html/modules $CURRENT_DIR/$SITE_ID/web/
cp -R $CURRENT_DIR/$BACKUP_DIR/homedir/public_html/themes $CURRENT_DIR/$SITE_ID/web/
cp -R $CURRENT_DIR/$BACKUP_DIR/homedir/public_html/libraries $CURRENT_DIR/$SITE_ID/web/


# Composerize the project
echo yes | composer composerize-drupal
composer remove drupal/md_slider # remove troublesome module which isn't managed by composer


# Install all the default projects - sendgrid integration, HSTS
composer require drupal/sendgrid_integration
composer require drupal/hsts
composer require drush/drush


# Update all composer projects and install everything
composer update
composer install


# Git commit and push
git add .
git commit -m "Composerized project and composer updates run."
git push

# ---------------------------------------------------------------------------- #


# Need to sync the files and the database to the server

# The database needs to be prepared

export DB_FILE_LOCATION=$CURRENT_DIR/$BACKUP_DIR/mysql/$DB_FILE_NAME
export PANTHEON_MYSQL_CONNECTION_COMMAND="$(terminus connection:info $SITE_ID.dev --field=mysql_command)"

eval $PANTHEON_MYSQL_CONNECTION_COMMAND < "$DB_FILE_LOCATION" --verbose

# Update the database schema and enable modules
terminus drush $SITE_ID.dev updb
terminus drush $SITE_ID.dev en hsts
terminus drush $SITE_ID.dev en sendgrid_integration


# Do some work before syncing files since we need time for the code to sync to dev

# Set the site into sftp mode so that we may export the configuration
terminus connection:set $SITE_ID.dev sftp

# Export full site config
terminus drush $SITE_ID.dev cex


# This takes a while, but IT WORKS! We need to do this in between drush cex.
cd $CURRENT_DIR/$BACKUP_DIR/homedir/public_html/sites/default/files
terminus rsync . $SITE_ID.dev:files


# We need to give the site some time to sync the code, cannot commit immediately
terminus env:commit $SITE_ID.dev --message="Exported full config"

# Set the site back into git connection mode
terminus connection:set $SITE_ID.dev git

# ---------------------------------------------------------------------------- #
