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

use strict;
use warnings;

use FindBin;
use lib "$FindBin::RealBin/regression";
use Slack;
use Compare;
use Diff;

#use List::Util qw(min max);

my $doHelp     = 0;
my $recipe     = undef;
my $regression = undef;
my $failed     = 0;
my $md5        = "md5sum";
my $postSlack  = 1;
my $refregr    = "(nothing)";

$md5 = "/sbin/md5"         if (-e "/sbin/md5");         #  BSDs.
$md5 = "/usr/bin/md5sum"   if (-e "/usr/bin/md5sum");   #  Linux.

while (scalar(@ARGV) > 0) {
    my $arg = shift @ARGV;

    if    ($arg eq "-recipe")     { $recipe     = shift @ARGV;      }
    elsif ($arg eq "-regression") { $regression = shift @ARGV;      }
    elsif ($arg eq "-fail")       { $failed     = 1;                }
    elsif ($arg eq "-no-slack")   { $postSlack  = 0;                }
    else                          { die "unknown option '$arg'.\n"; }
}

$doHelp = 1   if (!defined($recipe));
$doHelp = 1   if (!defined($regression));

if ($doHelp) {
    print STDERR "usage: $0 ...\n";
    print STDERR " MANDATORY:\n";
    print STDERR "  -recipe R       Name of recipe for this test.\n";
    print STDERR "  -regression R   Directory name of regression test.\n";
    print STDERR "\n";
    print STDERR " OPTIONAL:\n";
    print STDERR "  -fail           Report that the assembly failed to finish.\n";
    print STDERR "  -no-slack       If set, do not report results to Slack.\n";
    print STDERR "\n";
    exit(0);
}


#  Parse date-branch-hash from name, limit hash to 12 letters.
if ($regression =~ m/(\d\d\d\d-\d\d-\d\d-\d\d\d\d)(-*.*)-(............)/) {
    $regression = "$1$2-$3";
}


#  Parse and report job status if we failed.

if (! -e "assembly.fasta") {
    my %jobstat;

    if (open(F, "< ../$recipe-verkko.out")) {
        while (<F>) {
            if (m/Submitted\sjob\s(\d+)\s/) {
                print STDERR "SUBMITTED $1\n";
                $jobstat{$1} = "submitted";
            }
            if (m/Finished\sjob\s(\d+)./) {
                print STDERR "FINISHED  $1\n";
                delete $jobstat{$1};
            }
            if (m/Error\sexecuting\srule\s(.*)\son\scluster\s\(jobid:\s(\d+),\sexternal:\s(.*),/) {
                print STDERR "FAILED    $1\n";
                $jobstat{$2} = "$1/$3";
            }
            if (m/Trying\sto\srestart\sjob\s(\d+)./) {
                print STDERR "RESTART   $1\n";
                $jobstat{$1} = "restarted";
            }
        }
        close(F);
    }

    my $running;
    my $resub;
    my $failed;
    foreach my $id (sort {$a <=> $b} keys %jobstat) {
        if    ($jobstat{$id} eq "submitted") {
            if (defined($running)) {
                $running .= ", $id";
            } else {
                $running  = "$id";
            }
        }
        elsif ($jobstat{$id} eq "restarted") {
            if (defined($resub)) {
                $resub .= ", $id";
            } else {
                $resub  = "$id";
            }
        }
        else {
            if (defined($failed)) {
                $failed .= ", $jobstat{$id}:$id";
            } else {
                $failed  = "$jobstat{$id}:$id";
            }
        }
    }

    if ($postSlack == 1) {
        postHeading(":bangbang: *$recipe* crashed in _${regression}_.");
        postCodeBlock(undef, "Jobs running:\n$running\n")   if (defined($running));
        postCodeBlock(undef, "Jobs resub:\n$resub\n")       if (defined($resub));
        postCodeBlock(undef, "Jobs failed:\n$failed\n")     if (defined($failed));
    } else {
        print STDERR ("$recipe crashed in ${regression}.\n");
        print STDERR "Jobs running: $running\n"     if (defined($running));
        print STDERR "Jobs resubmitted: $resub\n"   if (defined($resub));
        print STDERR "Jobs failed: $failed\n"       if (defined($failed));
    }

    exit(1);
}

my @dr;

#  Attempt to figure out what we're comparing against.

{
    open(F, "ls -l ../../recipes/$recipe |");
    while (<F>) {
        if (m/refasm\s->\srefasm-(20.*-............)$/) {
            $refregr = $1;
        }
    }
    close(F);
}


#  Prepare for comparision!

my $IGNF = "";   #  To just ignore these reports.
my $newf = "";
my $misf = "";
my $samf = "";
my $diff = "";

my $IGNC = 0;
my $difc = 0;

my $report = "";

########################################
#  Check assembled contigs and the read layouts.  All we can do is report difference.
#

my $d01 = diffB(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "assembly.fasta");
my $d02 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "assembly.gfa");
my $d03 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "assembly.layout");

$report .= "*Contig sequences* have changed!  (but graph and layout are the same)\n"         if ( $d01 && !$d02 && !$d03);
$report .= "*Contig graph* has changed!  (but sequence and layout are the same)\n"           if (!$d01 &&  $d02 && !$d03);
$report .= "*Contig layouts* have changed!  (but sequence and graph are the same)\n"         if (!$d01 && !$d02 &&  $d03);

$report .= "*Contig sequences and graph* have changed!  (but layouts are the same)\n"        if ( $d01 &&  $d02 && !$d03);
$report .= "*Contig sequences and layouts* have changed!  (but graph is the same)\n"         if ( $d01 && !$d02 &&  $d03);
$report .= "*Contig graph and layouts* have changed!  (but sequences are the same)\n"        if (!$d01 &&  $d02 &&  $d03);

$report .= "*Contig sequences, graph and layouts* have all changed!\n"                       if ( $d01 &&  $d02 &&  $d03);

########################################
#  The primary check here is from quast.

my $d10 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/misassemblies_report.txt");
my $d11 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/transposed_report_misassemblies.txt");
my $d12 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/unaligned_report.txt");

my $d13 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/contigs_report_assembly.mis_contigs.info");
my $d14 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/contigs_report_assembly.unaligned.info");

if ($newf ne "") {
    $report .= "\n";
    $report .= "Files *without a reference* to compare against:\n";
    $report .= $newf;
}

if ($misf ne "") {
    $report .= "\n";
    $report .= "Files *missing* from the assembly:\n";
    $report .= $misf;
}

if ($d10 || $d11 || $d12 || $d13 || $d14) {
    $report .= "*quast/contigs_reports/misassemblies_report.txt* differs.\n"                   if ($d10);
    $report .= "*quast/contigs_reports/transposed_report_misassemblies.txt* differs.\n"        if ($d11);
    $report .= "*quast/contigs_reports/unaligned_report.txt* differs.\n"                       if ($d12);
    $report .= "*quast/contigs_reports/contigs_report_assembly.mis_contigs.info* differs.\n"   if ($d13);
    $report .= "*quast/contigs_reports/contigs_report_assembly.unaligned.info* differs.\n"     if ($d14);
}

########################################
#  Now do a detailed comparison of the quast results.

my $rlog = compareReport($recipe, "quast/report.tsv");
my @clog = compareContigReports($recipe, "quast/contigs_reports/contigs_report_assembly.stdout");

#$report .= "*Quast* has differences.\n"   if ($d10 || $d11 || $d12 || $d13 || $d14 || (defined $rlog) || scalar(@clog));

########################################
#  Report the results.

if (($difc == 0) && (! defined($rlog)) && (scalar(@clog) == 0)) {
    if ($postSlack == 1) {
        postHeading(":canu_success: *Report* for ${recipe}: *SUCCESS!*\n" .
                    "${regression} test assembly vs\n" .
                    "${refregr} reference assembly\n");
    } else {
        print "${recipe} passed!\n";
    }
}

else {
    if ($postSlack == 1) {
        postHeading(":canu_fail: *Report* for ${recipe} *significant differences exist*:\n" .
                    "${regression} test assembly vs\n" .
                    "${refregr} reference assembly\n");
        postFormattedText(undef, $report);

        if (defined($rlog)) {
            postHeading("*quast/report.tsv* has differences:");
            postFormattedText(undef, $rlog);
        } else {
            postHeading("*quast/report.tsv* has *no* differences.");
        }

        if (scalar(@clog) > 0) {
            postHeading("*quast/contigs_reports/contigs_report_assembly.stdout* has differences:");
            foreach my $log (@clog) {
                postFormattedText(undef, $log);
            }
        } else {
            postHeading("*quast/contigs_reports/contigs_report_assembly.stdout* has *no* differences:");
        }
    }

    else {
        print "$recipe FAILED!  $difc\n";
        print $report;

        if (defined($rlog)) {
            print "\n";
            print "quast/report.tsv differences:\n";
            print $rlog;
        }
        if (scalar(@clog) > 0) {
            print "\n";
            print "quast/contigs_reports/contigs_report_assembly.stdout differences:\n";
            foreach my $log (@clog) {
                print $log;
            }
        }
    }
}

#  And leave.

exit(0);
