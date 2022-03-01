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

use List::Util qw(min max);

#
#  Some functions first.  (Search for 'parse' to find the start of main.)
#

sub readFile ($$$) {
    my $file      = shift @_;
    my $linelimit = shift @_;
    my $sizelimit = shift @_;

    my $nl = 0;
    my $nb = 0;

    my $lines;

    print STDERR "READFILE $file\n";

    if (-e "$file") {
        open(F, "< $file");
        while (!eof(F) && ($nl < $linelimit) && ($nb < $sizelimit)) {
            $_ = <F>;

            $lines .= $_;

            $nl += 1;
            $nb += length($_);
        }
        close(F);
    }

    if (!defined($lines)) {
        return(undef);
    }

    return("${file}:\n```\n${lines}```\n");
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



sub saveQuastReportLine ($) {
    my ($k, $v) = split '\t', $_;

    chomp $k;
    chomp $v;

    if (($k =~ m/Assembly/) ||
        ($k =~ m/>=\s1000\sbp/) ||
        ($k =~ m/>=\s5000\sbp/) ||
        ($k =~ m/>=\s10000\sbp/) ||
        ($k =~ m/>=\s25000\sbp/) ||
        ($k =~ m/N50/) ||
        ($k =~ m/N75/) ||
        ($k =~ m/L50/) ||
        ($k =~ m/L75/) ||
        ($k =~ m/scaffold\sgap/) ||
        ($k =~ m/N.s\sper/) ||
        ($k =~ m/NA50/) ||
        ($k =~ m/NGA50/) ||
        ($k =~ m/NA75/) ||
        ($k =~ m/NGA75/) ||
        ($k =~ m/LA50/) ||
        ($k =~ m/LGA50/) ||
        ($k =~ m/LA75/) ||
        ($k =~ m/LGA75/)) {
        return(undef);
    }

    #  Report only 3 fraction digits instead of up to 10.
    if ($k =~ m/auN/) {
        $v = sprintf("%.3f", $v);
    }

    #  Report 'whole.part' instead of '0 + 9 part'.
    #if ($k =~ m/unaligned\scontig/) {
    #    if ($v =~ m/(\d+)\s\+\s(\d+)\spart/) {
    #        $v = sprintf("%d.%d", $1, $2);
    #    }
    #}

    return($k, $v);
}


sub diffQ ($$$$$$$@) {
    my $newf   = shift @_;   #  List of files that are only in the assembly
    my $misf   = shift @_;   #  List of files that are only in the reference (missing from the assembly)
    my $samf   = shift @_;   #  List of files that are the same, either identical files, or both missing
    my $diff   = shift @_;   #  List of files that are not the same
    my $difc   = shift @_;   #  Number of significant differences found.
    my $recipe = shift @_;
    my $file   = shift @_;

    my %key;

    my $reffile = "../../recipes/$recipe/refasm/$file";
    my %ref;
    my $asmfile = "./$file";
    my %asm;

    #  If BOTH are missing, they're the same.

    if ((! -e $asmfile) &&
        (! -e $reffile)) {
        $$samf .= "  $file\n";              return(0);
    }

    #  If either file isn't present, report a significant difference (but don't show details).

    if (! -e $reffile) { $$newf .= "  $file\n";   $$difc++;   return(0); }
    if (! -e $asmfile) { $$misf .= "  $file\n";   $$difc++;   return(0); }

    #  Load values from the reference report.

    open(F, "< $reffile");
    while (<F>) {
        my ($k, $v) = saveQuastReportLine($_);
        if (defined($v)) {
            $key{$k}++;
            $ref{$k} = $v;
        }
    }
    close(F);

    #  Load values from the regression report.

    open(F, "< $asmfile");
    while (<F>) {
        my ($k, $v) = saveQuastReportLine($_);
        if (defined($v)) {
            $key{$k}++;
            $asm{$k} = $v;
        }
    }
    close(F);

    #  Compare keys.  Report any differences.

    open(D, "> $file.diffs");

    print D sprintf("%-30s %15s %s %-15s\n", "Quast Measure", "REFERENCE", "", "REGRESSION");
    print D sprintf("%-30s %15s %s %-15s\n", "------------------------------", "---------------", "--", "---------------");

    my $diffs = 0;

    foreach my $k (sort keys %key) {
        my $r = $ref{$k};
        my $a = $asm{$k};
        my $c = "==";

        #  If either isn't defined, they're different.
        if    (!defined($r))  { $c = "!="; }
        elsif (!defined($a))  { $c = "!="; }

        #  Require exact match for some values.
        elsif (($k eq "# contigs") ||
               ($k eq "# contigs (>= 0 bp)") ||
               ($k eq "# contigs (>= 50000 bp)") ||
               ($k eq "# local misassemblies") ||
               ($k eq "# misassembled contigs") ||
               ($k eq "# misassemblies") ||
               ($k eq "# possible TEs") ||
               ($k eq "# unaligned contigs") ||   #  NOT an integer: '0 + 9 part'
               ($k eq "L90") ||
               ($k eq "LA90") ||
               ($k eq "LG50") ||
               ($k eq "LG90") ||
               ($k eq "LGA90")) {
            print "EXACT $k $r $a\n";
            if ($r ne $a) {
                $c = "!=";
            }
        }

        #  But allow some differences for all the rest.
        else {
            my $diff = abs($r - $a);
            my $ave  = ($r + $a) / 2;

            print "INEXACT $k $r $a - $diff $ave\n";

            if ($diff / $ave > 0.1) {
                $c = "!=";
            }
        }


        if ($c eq "!=") {
            print D sprintf("%-30s %15s %s %-15s\n", $k, $r, $c, $a);

            $diffs++;
        }
    }

    print D sprintf("%-30s %15s %s %15s\n", "------------------------------", "---------------", "--", "---------------");
    close(D);

    #  If differences exist, report a significant difference and show details.

    if ($diffs > 0) {
        $$diff .= "  $file\n";  $$difc++;   return(1);
    } else {
        $$samf .= "  $file\n";              return(0);
    }
}



sub filterQuastStdout ($$) {
    my $in = shift @_;
    my $ot = shift @_;
    my $lt;
    my $ml = 0;

    my @misasm;

    my ($type, $aid, $b1, $e1, $b2, $e2, $l1, $l2, $idt, $n1, $n2) = ("");

    open(IN, "< $in") or die "failed to open '$in' for reading: $!\n";
    while (<IN>) {
        s/^\s+//;
        s/\s+$//;

        #Real Alignment 1: 18027364 18061019 | 4 33649 | 33656 33646 | 99.92 | 2L tig00001804
        if (m!^\s*Real\sAlignment\s(\d+):\s(\d+)\s(\d+)\s\|\s(\d+)\s(\d+)\s\|\s(\d+)\s(\d+)\s\|\s(\d+.\d+)\s\|\s(.*)\s(.*)\s*$!) {
            if ($type ne "") {
                my $msg1 = sprintf("%15s %10d-%-10d %10d-%-10d %s\n", $n1, $b1, $e1, $2, $3, $9);
                my $msg2 = sprintf("%-23s %6.3f%%%15s%6.3f%%\n", $type, $idt, "", $8);
                my $msg3 = sprintf("%15s %10d-%-10d %10d-%-10d %s\n", $n2, $b2, $e2, $4, $5, $10);

                push @misasm, "$n1$b1\0\n$msg1$msg2$msg3";
            }

            ($type, $aid, $b1, $e1, $b2, $e2, $l1, $l2, $idt, $n1, $n2) = ("", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
        }

        if (m/^\s*Indel.*insertion\sof\slength\s(\d+);\s+(\d+)\smismat/) {
            $type = "INDEL $1 bp $2 mm";
        }
        if (m/^\s*Stretch\s+of\s+(\d+)\s+mismatches/) {
            $type = "MISMATCH $1 mm";
        }
        if (m/^\s*Extensive\smisassembly\s\(inversion\)\sbetween/) {
            $type = "INVERSION";
        }
        if (m/^\s*Extensive\smisassembly\s\(translocation\)\sbetween/) {
            $type = "TRANSLOCATION";
        }
        if (m/^\s*Extensive\smisassembly\s\(relocation,\sinconsistency\s=\s(-*[0-9]*)\)\sbetween/) {
            $type = "RELOCATION $1 bp";
        }
    }
    close(IN);

    @misasm = sort @misasm;

    open(OT, "> $ot") or die "failed to open '$ot' for writing: $!\n";
    foreach my $m (@misasm) {
        my ($pos, $msg) = split '\0', $m;
        print OT $msg;
    }
    close(OT);

    return $ml;
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
my @logs;


########################################
#  Check assembled contigs and the read layouts.  All we can do is report difference.
#

my $d06 = diffB(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "assembly.fasta");
my $d07 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "assembly.gfa");
my $d08 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "assembly.layout");

$report .= "*Contig sequences* have changed!  (but graph and layout are the same)\n"         if ( $d06 && !$d07 && !$d08);
$report .= "*Contig graph* has changed!  (but sequence and layout are the same)\n"           if (!$d06 &&  $d07 && !$d08);
$report .= "*Contig layouts* have changed!  (but sequence and graph are the same)\n"         if (!$d06 && !$d07 &&  $d08);

$report .= "*Contig sequences and graph* have changed!  (but layouts are the same)\n"        if ( $d06 &&  $d07 && !$d08);
$report .= "*Contig sequences and layouts* have changed!  (but graph is the same)\n"         if ( $d06 && !$d07 &&  $d08);
$report .= "*Contig graph and layouts* have changed!  (but sequences are the same)\n"        if (!$d06 &&  $d07 &&  $d08);

$report .= "*Contig sequences, graph and layouts* have all changed!\n"                       if ( $d06 &&  $d07 &&  $d08);

########################################
#  The primary check here is from quast.

my $d21 = diffQ(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/report.tsv");

my $d23 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/misassemblies_report.txt");
my $d24 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/transposed_report_misassemblies.txt");
my $d25 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/unaligned_report.txt");

my $d26 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/contigs_report_assembly.mis_contigs.info");
my $d27 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/contigs_report_assembly.unaligned.info");

my $qml = filterQuastStdout("quast/contigs_reports/contigs_report_assembly.stdout", "quast/contigs_reports/contigs_report_assembly.stdout.filtered");
my $d28 = diffA(\$newf, \$misf, \$samf, \$diff, \$difc, $recipe, "quast/contigs_reports/contigs_report_assembly.stdout.filtered", 2, $qml, 99);

$report .= "*Quast* has differences.\n"   if ($d21 || $d23 || $d24 || $d25 || $d26 || $d27 || $d28);

if ($d21) {
    push @logs, readFile("quast/report.tsv.diffs", 60, 8192);
}

#if ($d26) {
#    push @logs, readFile("quast/contigs_reports/contigs_report_assembly.mis_contigs.info.diffs", 60, 8192);
#}

#if ($d27) {
#    push @logs, readFile("quast/contigs_reports/contigs_report_assembly.unaligned.info.diffs", 60, 8192);
#}

if ($d28) {
    push @logs, readFile("quast/contigs_reports/contigs_report_assembly.stdout.filtered.diffs", 60, 8192);
}

#else {
#    push @logs, readFile("quast/contigs_reports/contigs_report_assembly.stdout.filtered", 60, 8192);
#}




#  Merge all the various differences found above into a single report.

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

#  Report the results.

if ($difc == 0) {
    my $head;

    $head  = ":canu_success: *Report* for ${recipe}:\n";
    $head .= "${regression} test assembly vs\n";
    $head .= "${refregr} reference assembly\n";

    # ":canu_success: *$recipe* has no differences between _${regression}_ and reference _${refregr}_.");

    if ($postSlack == 1) {
        postHeading($head);
    } else {
        print $head;
        #"SUCCESS $recipe has no differences between ${regression} and reference _${refregr}_.\n";
    }
}

else {
    my $head;

    $head  = ":canu_fail: *Report* for ${recipe} *significant differences exist*:\n";
    $head .= "${regression} test assembly vs\n";
    $head .= "${refregr} reference assembly\n";

    if ($postSlack == 1) {
        postHeading($head);
        postFormattedText(undef, $report);
        foreach my $log (@logs) {
            if (defined($log)) {
                postFormattedText(undef, $log);
            }
        }
    } else {
        print $head;
        print $report;
        foreach my $log (@logs) {
            if (defined($log)) {
                print "\n----------------------------------------\n";
                print $log;
            }
        }
    }
}

#  And leave.

exit(0);
