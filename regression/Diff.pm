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

package Diff;

require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(linediff diffA diffB);

use strict;
use warnings;



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

1;
