#!/bin/sh

###############################################################################
 #
 #  This file is part of verkko-regression, a package that tests the Verkko
 #  whole-genome assembler.
 #
 #  Except as indicated otherwise, this is a 'United States Government Work',
 #  and is released in the public domain.
 #
 #  File 'README.licenses' in the root directory of this distribution
 #  contains full conditions and disclaimers.
 ##

#
#  Given a path to a git repo, run a bunch of git commands to update it to
#  the latest remote master, and log what has changed.
#
#  If the repo is on a branch, the repo will be switched over to master.
#

cd $1

echo "########################################"
echo "#"
echo "#  INITIAL STATUS"
echo "#"

git status

echo ""
echo "########################################"
echo "#"
echo "#  REVERT TO PREVIOUS LATEST MASTER"
echo "#"

git checkout master
#git log --numstat ..origin/master
git merge

echo ""
echo "########################################"
echo "#"
echo "#  STATUS BEFORE UPDATING"
echo "#"

git status

echo ""
echo "########################################"
echo "#"
echo "#  FETCH NEW BITS"
echo "#"

git fetch

echo ""
echo "########################################"
echo "#"
echo "#  LOG OF NEW BITS"
echo "#"

git log --numstat ..origin/master

echo ""
echo "########################################"
echo "#"
echo "#  MERGE NEW BITS"
echo "#"

git merge

echo ""
echo "########################################"
echo "#"
echo "#  FINAL STATUS"
echo "#"

git status

exit 0
