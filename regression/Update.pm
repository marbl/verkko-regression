#!/usr/bin/env perl

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

package Update;

require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(updateRepo);

use strict;
use warnings;


#  Update a repo (either the main or a submodule) to the latest code and
#  build a log of what has changed.


sub runCommand ($$) {
    my $dir = shift @_;
    my $cmd = shift @_;
    my @lines;

    open(F, "cd $dir && $cmd 2>&1 |");
    while (<F>) {
        chomp;
        push @lines, $_;
    }
    close(F);

    return(@lines);
}



sub updateRepo ($) {
    my $dir        = shift @_;
    my $logsummary = "";
    my @lines;

    #
    #  Switch to the master branch, and make sure the code is up-to-date with
    #  it.  We don't really care what the output is, this is just to make the
    #  eventual 'merge' actually update the code for the master branch.
    #
    #  checkout will usually report:
    #      Already on 'master'
    #      Your branch is up to date with 'origin/master'.
    #
    #  merge will usually report:
    #      Already up to date.
    #

    #
    #  Report what we have now.  If it doesn't report
    #      On branch master
    #      Your branch is up to date with 'origin/master'.
    #
    #      nothing to commit, working tree clean
    #  then something is amiss and we should log it.
    #

    #  Final status should report:
    #    On branch master
    #    Your branch is up to date with 'origin/master'.
    #
    #    nothing to commit, working tree clean


    #  To update the repo and keep logs of what was done:
    #    - Make sure we're on the master branch.
    #    - Make sure that branch is up-to-date with what the
    #      local repo knows about.
    #    - Pull down new changes *only* for this repo, generate
    #      a log of them, and merge them into the current code.
    #
    my @initstat     = runCommand($dir, "git status");
    my @checkout     = runCommand($dir, "git checkout master");
    my @checkmerge   = runCommand($dir, "git merge");
    my @checkstatus  = runCommand($dir, "git status");

    my @newfetch     = runCommand($dir, "git fetch --no-recurse-submodules");
    my @newlogs      = runCommand($dir, "git log --numstat ..origin/master");

    my @newmerge     = runCommand($dir, "git merge");
    my @finalstatus  = runCommand($dir, "git status");

    #  Now that all the work is done, make sense of the logs and decide if
    #  anything has changed.

    #  We don't really care about @initstat, @checkout, @checkmerge.
    #  @checkstatus should report we are "On branch master" and "up to date".
    #  It'll probably report there is an untracked file 'date-to-hash'.

    if (($checkstatus[0] !~ m/branch master/) ||
        ($checkstatus[1] !~ m/up to date/)) {
    }

    #  The fetch will report a bunch of gunk, but also report
    #  status of tags:
    #  
    #      From github.com:marbl/canu
    #         76b1263fe..af771ef2c  master          -> origin/master
    #         21b8bd08d..14045343c  microasm_ovls_2 -> origin/microasm_ovls_2
    #       * [new branch]          trimming-test   -> origin/trimming-test
    #
    #  We parse it out....but never use it.

    my $oldhash = "";
    my $newhash = "";
    
    foreach my $line (@newfetch) {
        if ($line =~ m!^\s+(.*)\.\.(.*)\s+master\s+->\s+origin/master!) {
            $oldhash = $1;
            $newhash = $2;
        }
    }

    #  The log will have many items like
    #
    #      commit 095ed091e726ebb54a1307db597ec9a5cbaf20a1
    #      Author: Brian P. Walenz <thebri@gmail.com>
    #      Date:   Tue Dec 1 06:22:20 2020 -0500
    #
    #      Update utility/ again.  Don't use isdigit() or isspsace().
    #
    #      11      11      src/stores/objectStore.C
    #      1       1       src/stores/sqLibrary.H
    #      1       1       src/utility
    #      1       0       src/main.mk
    #
    #  We'll summarize this into two short lines.
    #
    #  A log such as the above will be parsed into three forms:
    #      src/WHERE/{stuff}   - WHERE is a subdirectory
    #      src/WHERE.{stuff}   - WHERE is a file in the root with some extension
    #      src/WHERE           - WHERE is a submodule

    my $author;
    my $date;
    my $log;
    my %where;

    foreach my $line (@newlogs) {
        if (!defined($author) && ($line =~ m!^Author:.*<(.*)\@.*>$!)) {
            $author = $1;
        }

        if (!defined($date) && ($line =~ m!^Date:\s+\w+\s+(\w+)\s+(\d+)\s+!)) {
            $date = "$1 $2";
        }

        if (!defined($log) && ($line =~ m!^\s+(.{0,60})(.*)$!)) {
            $log  = "\"";
            $log .= $1;
            $log .= "..."  if ($2 ne "");
            $log .= "\"";
        }

        if ($line =~ m!^\d+\s+\d+\s+(.*)!) {
            my @path = split '/', $1;

            if ($path[0] eq "src") {
                $where{$path[1]}++;
            } else {
                $where{$path[0]}++;
            }
        }

        if (defined($author) && ($line =~ m/^commit/)) {
            my $where = join '; ', keys %where;
            $logsummary .= "$author *on* $date: $log *in* $where.\n";

            undef $author;
            undef $date;
            undef $log;
            undef %where;
        }
    }


    if (defined($author)) {
        my $where = join '; ', keys %where;
        $logsummary .= "$author *on* $date: $log *in* $where.\n";

        undef $author;
        undef $date;
        undef $log;
        undef %where;
    }


    return($logsummary);
}

