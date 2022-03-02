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

package Compare;

require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(compareContigReports compareReport);

use strict;
use warnings;

#  A map from reference contig name to a unique integer used for sorting.
my %nameIdx;



sub loadContigReport ($) {
    my $report = shift @_;
    my @misasm;

    my ($type, $ml, $aid, $b1, $e1, $b2, $e2, $l1, $l2, $idt, $n1, $n2) = ("", 0);

    open(IN, "< $report") or die "failed to open '$report' for reading: $!\n";
    while (<IN>) {
        s/^\s+//;
        s/\s+$//;

        #  Parse an alignment line.  If there is a previously seen
        #  misassembly type, add a new missassembly record keyed
        #  on the begin location in the reference.
        #
        #  Real Alignment 1: 18027364 18061019 | 4 33649 | 33656 33646 | 99.92 | 2L tig00001804
        if (m!^\s*Real\sAlignment\s(\d+):\s(\d+)\s(\d+)\s\|\s(\d+)\s(\d+)\s\|\s(\d+)\s(\d+)\s\|\s(\d+.\d+)\s\|\s(.*)\s(.*)\s*$!) {
            if ($type ne "") {
                my $diff = "$n1$b1$e1$2$3$type$n2$b2$e2$4$5";
                my $msg1 = sprintf("%15s %9d-%-10d %9d-%-10d %s", $n1, $b1, $e1, $2, $3, $9);
                my $msg2 = sprintf("%-21s %7.3f%%%13s%7.3f%%", $type, $idt, "", $8);
                my $msg3 = sprintf("%15s %9d-%-10d %9d-%-10d %s", $n2, $b2, $e2, $4, $5, $10);

                if (!exists($nameIdx{$n1}))   { $nameIdx{$n1} = scalar(keys %nameIdx); }
                if (!exists($nameIdx{$n2}))   { $nameIdx{$n2} = scalar(keys %nameIdx); }
                if (!exists($nameIdx{$9}))    { $nameIdx{$9}  = scalar(keys %nameIdx); }
                if (!exists($nameIdx{$10}))   { $nameIdx{$10} = scalar(keys %nameIdx); }

                $ml = ($ml < length($msg1)) ? length($msg1) : $ml;
                $ml = ($ml < length($msg3)) ? length($msg2) : $ml;
                $ml = ($ml < length($msg3)) ? length($msg3) : $ml;

                my $loc = $nameIdx{$n1} * 1000000000 + $b1;

                push @misasm, "$loc\0$diff\0$msg1\0$msg2\0$msg3";
            }

            ($type, $aid, $b1, $e1, $b2, $e2, $l1, $l2, $idt, $n1, $n2) = ("", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
        }

        #  Check if the line is a misassembly that we care about (and some we
        #  don't care about).
        #
        if (m/^\s*Indel.*insertion\sof\slength\s(\d+);\s+(\d+)\smismat/) {
            $type = "INDEL $1 bp";
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

    @misasm = sort { (split('\0', $a))[0] <=> (split('\0', $b))[0] } @misasm;

    return($ml, @misasm);
}



sub compareContigReports ($$) {
    my $recipe = shift @_;
    my $report = shift @_;

    my ($refml, @refMis) = loadContigReport("../../recipes/$recipe/refasm/quast/contigs_reports/contigs_report_assembly.stdout");
    my ($regml, @regMis) = loadContigReport(                             "quast/contigs_reports/contigs_report_assembly.stdout");

    my @logs;

    while ((scalar(@refMis) > 0) ||
           (scalar(@regMis) > 0)) {
        my ($refkey, $refdiff, $ref1, $ref2, $ref3);
        my ($regkey, $regdiff, $reg1, $reg2, $reg3);
        my $diff = "";

        #  If only one report has a result, it's a difference.

        if    (scalar(@refMis) == 0) {
            ($regkey, $regdiff, $reg1, $reg2, $reg3) = split('\0', $regMis[0]);
            shift @regMis;
        }

        elsif (scalar(@regMis) == 0) {
            ($refkey, $refdiff, $ref1, $ref2, $ref3) = split('\0', $refMis[0]);
            shift @refMis;
        }

        #  Else, both reports have an entry.  Grab them and compare.
        else {
            ($refkey, $refdiff, $ref1, $ref2, $ref3) = split('\0', $refMis[0]);
            ($regkey, $regdiff, $reg1, $reg2, $reg3) = split('\0', $regMis[0]);

            if    ($refdiff eq $regdiff) {   #  The same!
                shift @refMis;
                shift @regMis;
            }
            elsif ($refkey == $regkey) {     #  The same _position_ but a different result.
                $diff = "yes";
                shift @refMis;
                shift @regMis;
            }
            elsif ($refkey < $regkey) {      #  Different position; reference is earlier.
                $diff = "ref";
                shift @refMis;
            }
            else {                           #  Different position; regression is earlier.
                $diff = "reg";
                shift @regMis;
            }
        }

        #  Now, depending on the comparison, display one or both of the entries.

        if      ($diff eq "ref") {
            my $log = (sprintf("```\n") .
                       sprintf("%-*s ][ *s\n", $refml, "REFERENCE ASSEMBLY", "REGRESSION ASSEMBLY") .
                       sprintf("%-*s ][\n", $refml, $ref1) .
                       sprintf("%-*s ][\n", $refml, $ref2) .
                       sprintf("%-*s ][\n", $refml, $ref3) .
                       sprintf("```\n"));
            push @logs, $log;
        } elsif ($diff eq "reg") {
            my $log = (sprintf("```\n") .
                       sprintf("%-*s ][ *s\n", $refml, "REFERENCE ASSEMBLY", "REGRESSION ASSEMBLY") .
                       sprintf("%-*s ][ %s\n", $refml, "", $reg1) .
                       sprintf("%-*s ][ %s\n", $refml, "", $reg2) .
                       sprintf("%-*s ][ %s\n", $refml, "", $reg3) .
                       sprintf("```\n"));
            push @logs, $log;
        } elsif ($diff eq "yes") {
            my $log = (sprintf("```\n") .
                       sprintf("%-*s ][ *s\n", $refml, "REFERENCE ASSEMBLY", "REGRESSION ASSEMBLY") .
                       sprintf("%-*s ][ %s\n", $refml, $ref1, $reg1) .
                       sprintf("%-*s ][ %s\n", $refml, $ref2, $reg2) .
                       sprintf("%-*s ][ %s\n", $refml, $ref3, $reg3) .
                       sprintf("```\n"));
            push @logs, $log;
        }
    }

    return(@logs);
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
    $v = sprintf("%.3f", $v)   if ($k =~ m/auN/);

    return($k, $v);
}



sub compareReport ($$) {
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
        return(0);
    }

    #  Load values from the reference report.

    #  If either file isn't present, report a significant difference (but don't show details).

    if (-e $reffile) {
        open(F, "< $reffile");
        while (<F>) {
            my ($k, $v) = saveQuastReportLine($_);
            if (defined($v)) {
                $key{$k}++;
                $ref{$k} = $v;
            }
        }
        close(F);
    }

    #  Load values from the regression report.

    if (-e $asmfile) {
        open(F, "< $asmfile");
        while (<F>) {
            my ($k, $v) = saveQuastReportLine($_);
            if (defined($v)) {
                $key{$k}++;
                $asm{$k} = $v;
            }
        }
        close(F);
    }

    #  Compare keys.  Report any differences.

    my $diffs = 0;
    my $log;

    $log  = sprintf("```\n");
    $log .= sprintf("%-30s %15s %2s %-15s\n", "Quast Measure", "REFERENCE", "", "REGRESSION");
    $log .= sprintf("%-30s %15s %2s %-15s\n", "------------------------------", "---------------", "--", "---------------");

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
            if ($r ne $a) {
                $c = "!=";
            }
        }

        #  But allow some differences for all the rest.
        else {
            my $dif = abs($r - $a);
            my $ave = ($r + $a) / 2;

            if ($dif / $ave > 0.1) {
                $c = "!=";
            }
        }

        if ($c eq "!=") {
            $diffs++;
            $log .= sprintf("%-30s %15s %s %-15s\n", $k, $r, $c, $a);
        }
    }

    $log .= sprintf("%-30s %15s %s %15s\n", "------------------------------", "---------------", "--", "---------------");
    $log .= sprintf("```\n");

    #  If no differences were found, forget the (empty) report.

    $log = undef   if ($diffs == 0);

    return($log);
}




1;
