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


sub branchExists ($$) {
    my $dir    = shift @_;
    my $branch = shift @_;
    my $found  = 0;

    print "branchExists($branch)-\n";

    my @branches = runCommand($dir, "git branch -a -vv");

    foreach (@branches) {
        $found = 1   if (m!remotes/origin/$branch!);
        print "branchExists($branch)- $found - $_\n";
    }

    return($found);
}


sub updateRepo ($$) {
    my $dir        = shift @_;
    my $branch     = shift @_;
    my $logsummary = "";

    #
    #  Fetch updates, then figure out where we should base changes from.
    #
    #  We need to remember if the branch exists before we fetch updates, so
    #  we can base logging from either the common ancestor (if it doesn't
    #  exist) or the last known commit in the branch.
    #
    #  This isn't really perfect, since there is no (easy) way to get the
    #  changes between the fetch and the last run of regression; we assume
    #  that whatever is in the repo before fetch is the last run.
    #
    #  There are three cases for finding where to report logs from:
    #    1) updating master               - use the current master HEAD
    #    2) updating a branch that exists - use the current branch HEAD
    #    3) the branch doesn't exist      - use the common ancestor
    #  
    #  (the first two are actually the same).
    #

    my $be    = branchExists($dir, $branch);
    my @fetch = runCommand($dir, "git fetch --no-recurse-submodules");
    my $logbase;

    if    ($branch eq "master") {
        $logbase = (runCommand($dir, "git rev-parse master"))[0];
        print "logbase 1 $logbase\n";
    }
    elsif ($be) {
        $logbase = (runCommand($dir, "git rev-parse $branch"))[0];
        print "logbase 2 $logbase\n";
    }
    else {
        $logbase = (runCommand($dir, "git merge-base master origin/$branch"))[0];
        print "logbase 3 $logbase\n";
    }

    #
    #  Pull the logs between the last state of the repo (or the common
    #  ancestor) and the state at github.
    #

    my @logs = runCommand($dir, "git log --numstat $logbase..origin/$branch");

    #
    #  And, finally, checkout that most recent branch.  This does leave us in
    #  a 'detached HEAD' state but we don't care as long as the bits are
    #  correct.
    #

    my @checkout = runCommand($dir, "git checkout $branch");
    my @merge    = runCommand($dir, "git merge --ff");



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

    foreach my $line (@logs) {
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

