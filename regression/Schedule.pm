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

package Schedule;

require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(findScheduleRecipes);

use strict;
use warnings;

use lib "$FindBin::RealBin/regression";
use Slack;

use Time::Local qw(timelocal);



sub loadScheduleFile ($$$$) {
    my $schedFile = shift @_;
    my $schedDay  = shift @_;
    my $schedSta  = shift @_;
    my $schedRec  = shift @_;

    open(F, "< $schedFile") or die "Failed to open schedule file '$schedFile'.\n";
    while (<F>) {
        s/^\s+//;
        s/\s+$//;

        next if (m/^#/);
        next if (m/^$/);

        my ($day, $sta, @rec) = split '\s+', $_;

        if    ($day eq "SUN")   { $day = 0; }
        elsif ($day eq "MON")   { $day = 1; }
        elsif ($day eq "TUE")   { $day = 2; }
        elsif ($day eq "WED")   { $day = 3; }
        elsif ($day eq "THR")   { $day = 4; }
        elsif ($day eq "FRI")   { $day = 5; }
        elsif ($day eq "SAT")   { $day = 6; }
        else                    { die "Invalid day-of-week '$day'.\n"; }

        push @$schedDay, $day;
        push @$schedSta, $sta;
        push @$schedRec, join ' ', @rec;

        printf STDERR "SCH - #%03d %s %s - %s\n", scalar(@$schedDay)-1, $day, $sta, (join ' ', @rec);
    }
    close(F);

    return(scalar(@$schedDay));
}



#  Find the index that is just before (or exactly) the current time.
#
sub findScheduleIndex ($$$$$) {
    my $nowWD    = shift @_;
    my $nowhh    = shift @_;
    my $nowmm    = shift @_;
    my $schedDay = shift @_;
    my $schedSta = shift @_;

    #  If we don't find one, the current time is after the last entry and
    #  before the first entry - which would mean the index we want is the
    #  last one.

    my $nextByTime = scalar(@$schedDay) - 1;

    for (my $idx=0; $idx < scalar(@$schedDay); $idx++) {
        my ($h, $m) = split ':', @$schedSta[$idx];

        if (((@$schedDay[$idx] < $nowWD)) ||
            ((@$schedDay[$idx] <= $nowWD) && ($h < $nowhh)) ||
            ((@$schedDay[$idx] <= $nowWD) && ($h <= $nowhh) && ($m <= $nowmm))) {
            $nextByTime = $idx;
            #printf STDERR "NEXT - #%03d %s %s\n", $idx, @$schedDay[$idx], @$schedSta[$idx];
            next;
        }

        #printf STDERR "LAST - #%03d %s %s\n", $idx, @$schedDay[$idx], @$schedSta[$idx];
        last;
    }

    return($nextByTime);
}



sub findNextStartTime ($$$$$$$$$$) {
    my ($nowWD, $nowYY, $nowMM, $nowDD, $nowhh, $nowmm, $nowss, $nextByTime, $schedDay, $schedSta) = @_;

    #  This isn't as straight forward as it seems.  We need to move the current time variables above
    #  up to the time listed in @$schedSta[$nextByTime].  In principle, we just need to set
    #  hh:mm:ss to the schedule time, then bump up DD until the weekday (WD) is the same as the
    #  schedule week day.  But the end of the month makes this complicated.  We can hardcode when
    #  the month ends -- except for leap years.
    #
    #  Instead we set the hh:mm to the schedule, convert to epoch seconds, add X * 86400 (24 * 60 *
    #  60) seconds to that and convert back to components.

    #  Reset time to the next schedule start time.
    if (@$schedSta[$nextByTime] =~ m/(\d+):(\d+)/) {
        $nowhh = $1;
        $nowmm = $2;
        $nowss =  0;
    } else {
        print STDERR "Failed to decode schedSta[$nextByTime] @$schedSta[$nextByTime] into hours:minutes.\n";
        $nowhh = 23;
        $nowmm = 59;
        $nowss = 50;
    }

    #  Convert to epoch seconds.
    my $epochsecs = timelocal($nowss, $nowmm, $nowhh, $nowDD, $nowMM-1, $nowYY);

    #  Adjust to the correct day.
    #
    #  If the next week day is after the current week day, add in the obvious difference in days.
    #
    #  If not, (say we went from nowWD=6 (SAT) to next=0 (SUN)) add a week of days to the next and
    #  then add in the obvious difference in days.

    if (@$schedDay[$nextByTime] >= $nowWD) {
        #printf STDERR "Add %d - %d = %d days to time\n", @$schedDay[$nextByTime], $nowWD, @$schedDay[$nextByTime] - $nowWD;
        $epochsecs += (@$schedDay[$nextByTime]     - $nowWD) * 86400;
    } else {
        #printf STDERR "Add %d - %d = %d days to time\n", @$schedDay[$nextByTime]+7, $nowWD, @$schedDay[$nextByTime]+7 - $nowWD;
        $epochsecs += (@$schedDay[$nextByTime] + 7 - $nowWD) * 86400;
    }

    #  Convert back to components and build properly formatted strings for sbatch/qsub.

    my ($nextss, $nextmm, $nexthh, $nextDD, $nextMM, $nextYY, $nextWD) = localtime($epochsecs);
    $nextMM += 1;
    $nextYY += 1900;

    my $qat = sprintf("%04d%02d%02d%02d%02d.00",  $nextYY, $nextMM, $nextDD, $nexthh, $nextmm);   #  For qsub
    my $sat = sprintf("%04d-%02d-%02d-%02d:%02d", $nextYY, $nextMM, $nextDD, $nexthh, $nextmm);   #  For sbatch

    #print "$qat $sat\n";

    return($qat, $sat);
}



#  Call this to get a space-separated list of recipes to run next.
#  Expects arguments:
#    nextBySched - the expected next schedule index to run
#    schedFile   - name of the text file with the schedule
#
sub findScheduleRecipes ($$) {
    my $nextBySched = shift @_;
    my $schedFile   = shift @_;

    #  Convert the epoch time to YYYY-MM-DD hh:mm:ss and a day-of-week.

    my ($nowss, $nowmm, $nowhh, $nowDD, $nowMM, $nowYY, $nowWD) = localtime(time());
    $nowMM += 1;
    $nowYY += 1900;

    #  Load and parse the schedule.

    my @schedDay;   #  Day of the week this event takes place
    my @schedSta;   #  Time of day this event should nominally start
    my @schedRec;   #  Recipes to run.

    my $maxIdx     = loadScheduleFile($schedFile, \@schedDay, \@schedSta, \@schedRec);

    #  Find the schedule index that the clock say should be run next.

    my $nextByTime = findScheduleIndex($nowWD, $nowhh, $nowmm, \@schedDay, \@schedSta);

    #  We want to run jobs for indexes $nextBySched (being the index of the jobs we expected to be
    #  running in this regression) through $nextByTime (being hte index of the jobs the current
    #  date/time say we should be running), wrapping around the end.
    #
    #  But if this script is run just a smidge before the expected time, we'll get the very bad
    #  result of wanting to run indices from X to X-1, in other words, ALL JOBS.  We guard against
    #  this by excluding that particular case.

    my @idxToRun;

    if (!defined($nextBySched)) {      #  If no -expected option is given, just run
        $nextBySched = $nextByTime;    #  the current jobs.
    }

    if ((($nextByTime + 1) % $maxIdx) == $nextBySched) {
        print STDERR "JOB EARLY.  Reset nextByTime = $nextByTime to nextBySched = $nextBySched\n";
        $nextByTime = $nextBySched;
    }

    if ($nextBySched <= $nextByTime) {
        for (my $idx=$nextBySched; $idx <= $nextByTime; $idx++) {
            push @idxToRun, $idx;
        }
    }
    else {
        for (my $idx=$nextBySched; $idx < $maxIdx; $idx++) {
            push @idxToRun, $idx;
        }
        for (my $idx=0; $idx <= $nextByTime; $idx++) {
            push @idxToRun, $idx;
        }
    }

    my %recipeList;

    foreach my $idx (@idxToRun) {
        my @r = split '\s+', $schedRec[$idx];

        #printf STDERR "RUN - #%03d %s %s - %s\n", $idx, $schedDay[$idx], $schedSta[$idx], $schedRec[$idx];

        foreach my $r (@r) {
            $recipeList{$r}++;
        }
    }

    #  Convert $nextByTime+1 into a string formatted for grid submission times - this is the time we
    #  want to start running the next regression run.

    my ($qat, $sat) = findNextStartTime($nowWD, $nowYY, $nowMM, $nowDD, $nowhh, $nowmm, $nowss, $nextByTime+1, \@schedDay, \@schedSta);

    #  Return all those goodies.

    return($nextByTime+1, $qat, $sat, keys %recipeList);
}

1;
