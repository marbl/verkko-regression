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

use List::Util qw(min max);

#
#  Some functions first.  (Search for 'parse' to find the start of main.)
#

sub readFile ($$$$) {
    my $logs      = shift @_;
    my $file      = shift @_;
    my $linelimit = shift @_;
    my $sizelimit = shift @_;

    my $nl = 0;
    my $nb = 0;

    my $lines;

    my $f = "${file}:\n";

    if (-e "$file") {
        open(F, "< $file");
        while (!eof(F)) {
            $_ = <F>;

            my $limit = (($nl < $linelimit) && ($nb < $sizelimit)) ? 0 : 1;
            my $empty = 0;

            $empty = 1  if ($_ =~ m/^\s*$/);
            $empty = 1  if ($_ =~ m/^=\s+\d+\s+\]\[\s*$/);

            if (($limit == 0) || ($empty == 0)) {
                $nl    += 1;
                $nb    += length($_);
                $lines .= $_;
            }

            else {
                print STDERR "EMPTY: $_";

                push @$logs, "$f```\n$lines```\n";

                undef $f;   #  Report the filename only once.

                $nl     = 0;
                $nb     = 0;
                $lines  = "";
            }

        }

        close(F);
    }

    if (defined($lines)) {
        push @$logs, "$f```\n$lines```\n";
    }
}



sub linediffprint ($) {
    my $l = shift @_;

    $l =~ s/\s+$//;

    return("$l\n");
}

sub linediff ($$$$@) {
    my $reffile = shift @_;
    my $asmfile = shift @_;
    my $outfile = shift @_;
    my $n       = shift @_;   #  Width of line number in report.
    my $w       = shift @_;   #  Max length of a line in the report (per file).
    my $l       = 1;
    my $m       = shift @_;   #  Max number of lines to process.
    my $context = 5;

    $n =        8   if (!defined($n) || ($n == 0));
    $w =      100   if (!defined($w) || ($w == 0));
    $m = 10000000   if (!defined($m) || ($m == 0));

    my $hfmt = "  %-${n}s %${w}.${w}s ][ %-${w}.${w}s\n";
    my $dfmt = "! %-${n}d %-${w}.${w}s ][ %-${w}.${w}s\n";
    my $sfmt = "= %-${n}d %-${w}.${w}s ][ %-${w}.${w}s\n";

    open(A, "< $reffile");
    open(B, "< $asmfile");
    open(O, "> $outfile");

    print O linediffprint(sprintf($hfmt, " ", "REFERENCE ASSEMBLY", "REGRESSION ASSEMBLY"));

    my @hist;
    my $extraP = 0;

    while ((!eof(A) ||
            !eof(B)) &&
           ($l <= $m)) {
        my $a = <A>;
        my $b = <B>;

        $a = ""   if (!defined($a));
        $b = ""   if (!defined($b));

        $a =~ s/\t/ /g;
        $b =~ s/\t/ /g;

        chomp $a;
        chomp $b;

        if ($a ne $b) {
            foreach my $h (@hist) {
                print O $h;
            }
            undef @hist;
            print O linediffprint(sprintf($dfmt, $l, $a, $b));
            $extraP = $context;
        }
        else {
            if ($extraP > 0) {
                $extraP--;
                print O linediffprint(sprintf($sfmt, $l, $a, $b));
            } else {
                push @hist, linediffprint(sprintf($sfmt, $l, $a, $b));
                if (scalar(@hist) > $context) {
                    shift @hist;
                }
            }
        }

        $l++;
    }

    close(A);
    close(B);
    close(O);
}



#  Compare an ASCII output file against the refefremce.
#
#  Returns true if there is a log difference to show.
#
#  Appends the filename to newf, misf, samf, diff based on how it differs from the reference.
#  Adds one to difc if the results are different.
#
sub diffA ($$$$$$$@) {
    my $newf   = shift @_;   #  List of files that are only in the assembly
    my $misf   = shift @_;   #  List of files that are only in the reference (missing from the assembly)
    my $samf   = shift @_;   #  List of files that are the same, either identical files, or both missing
    my $diff   = shift @_;   #  List of files that are not the same
    my $difc   = shift @_;   #  Number of significant differences found.
    my $recipe = shift @_;
    my $file   = shift @_;
    my $n      = shift @_;   #  optional, see linediff() above
    my $w      = shift @_;   #  optional, see linediff() above
    my $m      = shift @_;   #  optional, see linediff() above

    my $reffile = "../../recipes/$recipe/refasm/$file";
    my $asmfile = "./$file";

    my $refpresent = -e $reffile ? 1 : 0;
    my $asmpresent = -e $asmfile ? 1 : 0;

    if (($refpresent == 0) && ($asmpresent == 0))  { $$samf .= "  $file\n";             return(0); }
    if (($refpresent == 1) && ($asmpresent == 0))  { $$misf .= "  $file\n";  $$difc++;  return(0); }
    if (($refpresent == 0) && ($asmpresent == 1))  { $$newf .= "  $file\n";  $$difc++;  return(0); }

    #  Both files exist.  Compare them.

    my $refsum = `cat $reffile | shasum`;
    my $asmsum = `cat $asmfile | shasum`;

    if ($refsum eq $asmsum)  { $$samf .= "  $file\n";             return(0); }
    else                     { $$diff .= "  $file\n";  $$difc++;             }

    linediff($reffile, $asmfile, "$asmfile.diffs", $n, $w, $m);

    return(1);
}



#  Compare a BINARY output file against the refefremce.
#
#  Input and output are the same as diffA() above.
#
sub diffB ($$$$$$$) {
    my $newf   = shift @_;
    my $misf   = shift @_;
    my $samf   = shift @_;
    my $diff   = shift @_;
    my $difc   = shift @_;
    my $recipe = shift @_;
    my $file   = shift @_;

    my $reffile = "../../recipes/$recipe/refasm/$file";
    my $asmfile = "./$file";

    my $refpresent = -e $reffile ? 1 : 0;
    my $asmpresent = -e $asmfile ? 1 : 0;

    if (($refpresent == 0) && ($asmpresent == 0))  { $$samf .= "  $file\n";             return(0); }
    if (($refpresent == 1) && ($asmpresent == 0))  { $$misf .= "  $file\n";  $$difc++;  return(0); }
    if (($refpresent == 0) && ($asmpresent == 1))  { $$newf .= "  $file\n";  $$difc++;  return(0); }

    #  Both files exist.  Compare them.

    my $refsum = `cat $reffile | shasum`;
    my $asmsum = `cat $asmfile | shasum`;

    if ($refsum eq $asmsum)  { $$samf .= "  $file\n";             return(0); }
    else                     { $$diff .= "  $file\n";  $$difc++;  return(1); }
}


#
#  Parse the command line.
#

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

    if    ($arg eq "-recipe") {
        $recipe = shift @ARGV;
    }

    elsif ($arg eq "-regression") {
        $regression = shift @ARGV;

        #  Parse date-branch-hash from name, limit hash to 12 letters.
        if ($regression =~ m/(\d\d\d\d-\d\d-\d\d-\d\d\d\d)(-*.*)-(............)/) {
            $regression = "$1$2-$3";
        }
    }

    elsif ($arg eq "-fail") {
        $failed = 1;
    }

    elsif ($arg eq "-no-slack") {
        $postSlack = 0;
    }

    else {
        die "unknown option '$arg'.\n";
    }
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
    print STDERR "\n";
    print STDERR "  -no-slack       If set, do not report results to Slack.\n";
    print STDERR "\n";
    exit(0);
}


#if (! -e "assembly.fasta") {
#    $failed = 1;
#}

if ($failed) {
    my %jobstat;

    if (open(F, "< ../$recipe-verkko.out")) {
        while (<F>) {
            if (m/Submitted\sjob\s(\d+)\s/) {
                $jobstat{$1} = "submitted";
            }
            if (m/Finished\sjob\s(\d+)./) {
                delete $jobstat{$1};
            }
            if (m/Error\sexecuting\srule\s(.*)\son\scluster\s\(jobid:\s(\d+),\sexternal:\s(.*),/) {
                $jobstat{$2} = "$1/$3";
            }
            if (m/Trying\sto\srestart\sjob\s(\d+)./) {
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
