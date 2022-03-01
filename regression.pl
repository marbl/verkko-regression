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
use Update;
use Schedule;

use Time::Local qw(timelocal);
use Cwd qw(getcwd abs_path);

my $doHelp    = 0;
my $doList    = "";
my $errs      = "";
my $doFetch   = 1;
my $date      = undef;
my $repo      = "verkko";
my $branch    = "master";
my $hash      = undef;
my $path      = "";
my $resub     = "no";        #  Time of submission and time of resubmission.
my $ropts     = "";          #  Options passed to resubmission.
my $sched     = undef;
my $schedNext = undef;

my $wrkdir    = abs_path(".");
my $gitrepo   = abs_path("$repo-master-repo");          #  NEEDS to be full path, not relative, for rsync.

my $tz        = `date +%z`;              chomp $tz;     #  What timezone we're in.
my $now       = `date +%Y-%m-%d-%H%M`;   chomp $now;    #  Current date and time.
my $dow       = `date +%w`;              chomp $dow;    #  Day of week, used to decide when to run big tests.

my $regr      = undef;      #  Eventually set to "$date-$branch-$hash"
my $tests     = undef;
my @recipes;

#
#  Parse the command line, saving options into $ropts so we can restart
#  ourself.
#

sub saveOpt ($) {
    if (length($ropts) > 0) {
        $ropts .= " $_[0]";
    } else {
        $ropts  =  "$_[0]";
    }
}

while (scalar(@ARGV) > 0) {
    my $arg  = shift @ARGV;
    my $test = $arg;
    my $recp = $arg;

    $test =~ s/-//;
    $test =~ tr/a-z/A-Z/;
    $test =  "zzz$test";

    $recp =~ s!recipes/!!;

    if   (($arg eq "-h") ||
          ($arg eq "-help")) {
        $doHelp  = 1;
    }

    elsif ($arg eq "-list-refs")       { $doList = "refs"; }
    elsif ($arg eq "-list-assemblies") { $doList = "asms"; }
    elsif ($arg eq "-list-completed")  { $doList = "fini"; }
    elsif ($arg eq "-list-missing")    { $doList = "miss"; }
    elsif ($arg eq "-list-failed")     { $doList = "fail"; }

    elsif ($arg eq "-fetch") {
        $doFetch = 1;
        saveOpt($arg);
    }

    elsif ($arg eq "-no-fetch") {
        $doFetch = 0;
        saveOpt($arg);
    }

    elsif ($arg eq "-branch") {
        $branch  = shift @ARGV;
        saveOpt("$arg $branch");
    }

    elsif ($arg eq "-master") {
        $branch  = "master";
        saveOpt($arg);
    }

    elsif ($arg eq "-latest") {
        $hash    = undef;
        $date    = $now;
        saveOpt($arg);
    }

    elsif ($arg eq "-hash") {
        $hash    = shift @ARGV;
        $date    = undef;
        saveOpt("$arg $hash");
    }

    elsif ($arg eq "-date") {
        $hash    = undef;
        $date    = shift @ARGV;
        saveOpt("$arg $date");
    }

    elsif ($arg eq "-path") {
        $doFetch = 0;
        $path    = shift @ARGV;
        $hash    = undef;
        $date    = $now;
        saveOpt("$arg $path");
    }

    elsif ($arg eq "-schedule") {
        $sched     = shift @ARGV;
    }

    elsif ($arg eq "-expected") {
        $schedNext = shift @ARGV;
    }

    elsif (-e "recipes/$test")           {  $tests = $test;        saveOpt($arg);  }
    elsif (-e "recipes/$recp/submit.sh") {  push @recipes, $recp;  saveOpt($arg);  }

    else {
        $errs .= "ERROR: Unknown option '$arg'.\n";
    }
}

$errs .= "ERROR: Exactly one of -latest, -date, -hash or -path must be supplied.\n"   if (!defined($date) && !defined($hash) && ($path eq "") && ($doList eq "")) ;
$errs .= "ERROR: Exactly one of -latest, -date, -hash or -path must be supplied.\n"   if ( defined($date) &&  defined($hash) && ($path eq "") && ($doList eq "")) ;
$errs .= "ERROR: Test file 'recipe/$tests' doesn't exist.\n"                          if ((defined($tests)) && (! -e "recipes/$tests"));
$errs .= "ERROR: -path path must be to root of git clone.\n"                          if (($path ne "") && (! -e "$path/.git"));


if (($doHelp) || ($errs ne "")) {
    print "usage: $0 [options] [recipe-class | recipe-list]\n";
    print "\n";
    print "CODE UPDATE\n";
    print "  -(no-)fetch  Fetch (or not) updates to the repository.\n";
    print "\n";
    print "REPORTS\n";
    print "  -list-refs        List the current reference assemblies.\n";
    print "  -list-assemblies  List the assemblies and status of each (the union of the next three reports).\n";
    print "  -list-completed   List the assemblies that have completed.\n";
    print "  -list-missing     List the assemblies that have not been started in an existing regression set.\n";
    print "  -list-failed      List the assemblies that have failed to complete.\n";
    print "\n";
    print "BRANCH SELECTION\n";
    print "  -branch B    Test branch 'B'.\n";
    print "  -master      Test the master branch (default).\n";
    print "\n";
    print "CODE SELECTION (exactly one must be supplied)\n";
    print "  -latest      Use the latest code.\n";
    print "  -hash H      Use a specific historical hash.\n";
    print "  -date D      Use a specific historical date.  Format YYYY-MM-DD-HHMM.\n";
    print "\n";
    print "  -path P      Use a pre-compiled version found in path P.\n";
    print "\n";
    print "TEST SELECTION (exactly one must be supplied)\n";
    print "  CLASS        Run tests listed in recipes/zzzCLASS\n";
    print "  recipe/NAME  Run test recipe/NAME\n";
    print "\n";
    print "RECURRENCY\n";
    print "  -schedule s  Read the testing schedule from file 's'.  The format is multiple lines of:\n";
    print "                   DayOfWeek  NominalStartTime  NegOffset  PosOffset  recipes ...\n";
    print "\n";
    print "                 DayOfWeek        - SUN, MON, TUE, WED, THR, FRI, SAT\n";
    print "                 NominalStartTime - In 24-hour HH:MM format.\n";
    print "                 recipes          - space separated list of recipes to run\n";
    print "\n";
    print "                 This file MUST be sorted by time, with SUN = 0.\n";
    print "\n";
    print "  -expected x  Submit another regression run to the grid.  'x' must be an integer between 0 and\n";
    print "               the number of lines in the schedule file indicating the entry of the expected task\n";
    print "               to run.  Regression jobs between that expected task and the current time will be\n";
    print "               performed.  Generally only supplied on automatic resubmissions, not by humans.\n";
    print "\n";
    print "Logging ends up in Slack.  Some trivial progress is reported to stdout.\n";
    print "\n";

    print "$errs\n"   if ($errs ne "");

    exit(0);
}


if ($doList eq "refs") {
    my %refs;
    my @asms;
    my $mLen = 0;
    my $nRef = 0;
    my $wRef = 0;

    #  Build a map from recipe to reference assembly.
    open(F, "ls -l recipes/*/refasm |");
    while (<F>) {
        $refs{$1} = $2   if (m!\srecipes/(\S*)/refasm\s->\s(\S+)$!);
    }
    close(F);

    #  Build a list of the assemblies we know about, remember the length of
    #  the longest name (for pretty-printing) and count how assemblies many
    #  have or do not have a reference assembly.
    open(F, "ls -l recipes/*/submit.sh |");
    while (<F>) {
        if (m!\srecipes/(\S*)/submit.sh$!) {
            push @asms, $1;

            $mLen = ($mLen < length($1)) ? length($1) : $mLen;

            $nRef++   if (!exists($refs{$1}));
            $wRef++   if ( exists($refs{$1}));
        }
    }
    close(F);

    #  If assemblies without a reference exist, print them.
    if ($nRef) {
        print "\n";
        print "Assemblies without references:\n";

        foreach my $asm (sort @asms) {
            printf("  %-*s -> no reference assembly\n", $mLen, $asm)   if (!exists($refs{$asm}));
        }
    }

    #  If assemblies with a reference exist, print the reference assembly mapping.
    if ($wRef) {
        print "\n";
        print "Current reference assebmlies:\n";

        foreach my $asm (sort keys %refs) {
            printf("  %-*s -> %s\n", $mLen, $asm, $refs{$asm});
        }
    }

    exit(0);
}


if (($doList eq "asms") ||
    ($doList eq "fini") ||
    ($doList eq "miss") ||
    ($doList eq "fail")) {
    my @asms;
    my @regr;

    my $mLen = 0;

    open(F, "ls -l recipes/*/submit.sh |");
    while (<F>) {
        if (m!\srecipes/(\S*)/submit.sh$!) {
            push @asms, $1;

            $mLen = ($mLen < length($1)) ? length($1) : $mLen;
        }
    }
    close(F);

    open(F, "ls -d 20* |");
    while (<F>) {
        if (m!(\d\d\d\d-\d\d-\d\d-\d\d\d\d-\S+-............)$!) {
            push @regr, $1;

            $mLen = ($mLen < length($1)) ? length($1) : $mLen;
        }
    }
    close(F);

    foreach my $asm (sort @asms) {
        my @results;
        my $show = 0;

        foreach my $reg (sort @regr) {
            my $sta = (-e "$reg/$asm-submit.sh")         ? "YES" : "no";   #  Started?
            my $ctg = (-e "$reg/$asm/asm.contigs.fasta") ? "YES" : "no";   #  Contigs exist?
            my $qst = (-e "$reg/$asm/quast/report.txt")  ? "YES" : "no";   #  Quast exists?

            #  Some horrible if tests here.  Show results if:
            #    -list-assemblies; (show everything)
            #    -list-completed  and any of the above three tests are true.
            #    -list-missing    and the assembly was not started.
            #    -list-failed     and the assembly was started but not finished.
            #
            $show = 1   if (($doList eq "asms"));
            $show = 1   if (($doList eq "fini") && (($sta eq "YES") ||  ($ctg eq "YES") || ($qst eq "YES")));
            $show = 1   if (($doList eq "miss") && (($sta eq  "no")));
            $show = 1   if (($doList eq "fail") &&  ($sta eq "YES") && (($ctg eq  "no") || ($qst eq  "no")));

            #  Then add this assembly result to the output list if:
            #    -list-assemblies; (show everything)
            #    -list-completed and it was at least started.
            #    -list-missing   and it was not started.
            #    -list-failed    and it was started but not finished.
            #
            if ((($doList eq "asms")) ||
                (($doList eq "fini") &&  ($sta eq "YES")) ||
                (($doList eq "miss") &&  ($sta eq  "no")) ||
                (($doList eq "fail") && (($sta eq "YES") && (($ctg ne "YES") || ($qst ne "YES"))))) {
                push @results, sprintf("%-*s  %7s  %7s  %5s\n", $mLen, $reg, $sta, $ctg, $qst);
            }
        }

        if (($show) && (scalar(@results > 0))) {
            printf("\n");
            printf("%-*s  Started  Contigs  Quast\n", $mLen, $asm);
            printf("-" x $mLen . "  -------  -------  -----\n");
            foreach my $res (@results) {
                print $res;
            }
        }
    }

    exit(0);
}


#
#  Make sure we can write stuff to slack.  All the logs and results go there.
#

checkSlack();

#
#  CLONE: If there's no repo (and we're not running from a local copy) clone
#  the repo from github.
#

if (($doFetch) && ($path eq "") && (! -d $gitrepo)) {
    my $lines;

    print STDERR "Cloning initial repo.\n";

    system("mkdir -p $gitrepo");
    system("git clone --recurse-submodules https://github.com/marbl/$repo.git $gitrepo > clone.log 2>&1");

    open(F, "< clone.log");
    while (<F>) {
        next   if ($_ =~ m/Updating\sfiles/);
        $lines .= $_;
    }
    close(F);

    unlink "clone.log";

    postFormattedText("*Clone $repo* into '$gitrepo'.", $lines);
}

#
#  SWITCH BRANCH: Switch the repo to the requested branch if we're not there
#  already.
#

if (($path eq "") && (-d $gitrepo)) {
    my $onBranch = "";

    open(F, "cd $gitrepo && git status |");
    while (<F>) {
        $onBranch = $1   if (m/^On\s+branch\s+(.*)$/);
    }
    close(F);

    if ($onBranch ne $branch) {
        my $lines;

        system("cd $gitrepo && git checkout $branch             > checkout.log 2>&1");
        system("cd $gitrepo && git submodule update --recursive > update.log   2>&1");

        open(F, "< $gitrepo/checkout.log");
        while (<F>) {
            next   if ($_ =~ m/^Switched\sto/);
            next   if ($_ =~ m/^Your\sbranch\sis\sup\sto\sdate\swith/);
            $lines .= $_;
        }
        close(F);

        unlink "$gitrepo/checkout.log";
        unlink "$gitrepo/update.log";

        postFormattedText("*Switch from branch '$onBranch' to branch '$branch'.*", $lines);
    }
}

#
#  FETCH UPDATES: Fetch and apply any updates.  This could be done _before_
#  switching to the correct branch, but then we'd need to do basically the
#  same thing again to update the branch we just switched to.
#
#  Posting of the logs is disabled because they're a bit verbose.
#

if (($doFetch) && ($path eq "") && (-d $gitrepo)) {
    my @rp;
    my @ch;

    push @rp, "$gitrepo";
    push @ch, updateRepo("$gitrepo");

    open(F, "cd $gitrepo && git submodule status --recursive |");
    while (<F>) {
        chomp;

        if (m/^.(.*)\s+(.*)\s\((.*)\)$/) {
            push @rp, "$2 ($3)";
            push @ch, updateRepo("$gitrepo/$2");
        } else {
            push @rp, "PARSE FAILURE";
            push @ch, "$_\n";
        }
    }
    close(F);

    if (join("", @ch) ne "") {
        postHeading("*Update $repo* branch $branch in '$gitrepo'.");

        while (scalar(@rp) > 0) {
            my $rp = shift @rp;
            my $ch = shift @ch;
            postFormattedText("*$rp changes*:", $ch)   if ($ch ne "");
        }
    } else {
        postHeading("*No changes* for branch $branch in '$gitrepo'.");
    }
}

#
#  PICK VERSION: Update the list of revisions, then map the date to a hash,
#  then find the date for that hash.
#

system("cd $gitrepo && git log --date=format-local:%Y-%m-%d-%H%M --pretty=tformat:'%ad %H' | sort -nr > date-to-hash");

if (defined($date)) {
    my $bestdate;
    my $besthash;
    my $trigger  = 0;

    open(F, "< $gitrepo/date-to-hash") or die "Failed to open '$gitrepo/date-to-hash' for reading: $!\n";
    while (<F>) {
        chomp;

        if (m/^(\d\d\d\d-\d\d-\d\d-\d\d\d\d)\s+(.*)$/) {
            my $d = $1;
            my $h = $2;

            if ($d le $date) {
                $bestdate = $d;
                $besthash = $h;

                last;
            }
        } else {
            die "Malformed date-to-hash: '$_'\n";
        }
    }
    close(F);

    die "No bestdate?\n"   if (!defined($bestdate));

    $hash = $besthash;
}

if (!defined($hash)) {
    die "Failed to find a hash?\n";
}

if (defined($hash)) {
    my @matches;
    my $hl = length($hash);
    my $hf;

    open(F, "< $gitrepo/date-to-hash") or die "Failed to open '$gitrepo/date-to-hash' for reading: $!\n";
    while (<F>) {
        chomp;

        if (m/^(\d\d\d\d-\d\d-\d\d-\d\d\d\d)\s+(.*)$/) {
            my $d = $1;
            my $h = substr($2, 0, $hl);

            #print STDERR "TEST hash '$hash' vs '$d' '$h' from $2\n";
            if ($hash eq $h) {
                $date = $d;
                $hf   = $2;
                push @matches, $_;
            }
        } else {
            die "Malformed date-to-hash: '$_'\n";
        }
    }
    close(F);

    if    (scalar(@matches) == 0) {
        die "Failed to find date for hash $hash.  Wrong branch?\n";
    }
    elsif (scalar(@matches) == 1) {
        if ($hl < 40) {
            print STDERR "Found date $date for hash prefix $hash (full hash $hf)\n";
        } else {
            print STDERR "Found date $date for hash $hash\n";
        }

        $hash = $hf;
        $regr = "$date-$branch-" . substr($hash, 0, 12);
    }
    else {
        print STDERR "Multiple matches for hash $hash:\n";
        foreach my $m (@matches) {
            print STDERR "  $m\n";
        }
        die "Pick one and restart.\n";
    }
}

#
#  CHECK OUT: Check out a specific version.  We're already on the correct
#  branch, so just copy the repo and checkout/update the code.
#
#  If a path to a specific tree is used, just copy the tree over.
#
#  The double checkout is to just get a clean log.  The first checkout
#  'falsely' reports that submodules are out-of-date.
#

if (! -d "$wrkdir/$regr/$repo") {
    if ($path eq "") {
        system("mkdir -p $wrkdir/$regr/$repo");
        system("cd $wrkdir/$regr/$repo && rsync -a $gitrepo/ .");
        system("cd $wrkdir/$regr/$repo && git checkout $hash                > initial-checkout.log 2>&1");
        system("cd $wrkdir/$regr/$repo && git submodule update --recursive  > checkout.log 2>&1");
        system("cd $wrkdir/$regr/$repo && git checkout $hash               >> checkout.log 2>&1");

        postFile("*Checkout $date $hash*.", "$wrkdir/$regr/$repo/checkout.log");
    }
    else {
        postHeading("*Using* '$path'.");

        system("mkdir -p $wrkdir/$regr/$repo");
        system("cd $wrkdir/$regr/$repo && rsync -a $path/ .");
    }
}

#
#  COMPILE: Compile it.  Should we also remove any previous build?
#

if (! -e "$wrkdir/$regr/$repo/src/make.log") {
    postHeading("*Build*.");

    system("cd $wrkdir/$regr/$repo/src && gmake -j 8 > make.log 2> make.log");   #  Once, with threads.
    system("cd $wrkdir/$regr/$repo/src && gmake      > make.log 2> make.log");   #  Again, without, to get errors.

    #
    #  Check for compilation errors.
    #

    my $isOK = 0;
    my $ot = "";
    my $ce = "";

    open(ERRS, "< $wrkdir/$regr/$repo/src/make.log");
    while (! eof(ERRS)) {
        $_ = <ERRS>;

        if (m/^Success!\s*$/) {
            $isOK=1;
        }

        $ot .= $_;
    }
    close(F);

    open(ERRS, "< $wrkdir/$regr/$repo/src/make.log");
    while (! eof(ERRS)) {
        $_ = <ERRS>;

        next   if (m/At\sglobal\sscope/);
        next   if (m/unrecognized\scommand\sline\soption/);
        next   if (m/^ar:/);

        if (m/warning:\s#warning/) {
            #$wn .= $_;
            $_ = <ERRS>;
            $_ = <ERRS>;
            next;
        }

        $ce .= $_;
    }
    close(F);

    if ($isOK) {
        postCodeBlock(undef, $ot);
        postHeading(":canu_success: *Build was successful*.");
    }

    else {
        postCodeBlock(undef, $ot);
        postCodeBlock(undef, $ce);
        postHeading(":canu_fail: *BUILD FAILED*.");

        exit(1);
    }
}

#
#  FIND TEST CASES: Find stuff to run.  We were either given a specific
#  recipe to use, or a recipe file.
#

if (defined($tests) && -e "recipes/$tests") {
    open(F, "< recipes/$tests");
    while (<F>) {
        chomp;
        push @recipes, "$_"   if (-e "recipes/$_/submit.sh");
    }
    close(F);
}

#
#  But if we're following a schedule, use those recipes instead.
#

my $nextByDate;   #  Index of next schedule run.
my $qat;          #  SGE qsub     formatted date of when to run again.
my $sat;          #  Slurm sbatch formatted date of when to run again.

if (defined($sched)) {
    ($nextByDate, $qat, $sat, @recipes) = findScheduleRecipes($schedNext, $sched);
}

#
#  EXECUTE: And run them.
#

if (scalar(@recipes) == 0) {
    print "NO RECIPES supplied; no tests started.\n";
}

my $nExist    = 0;   #  Num tests that have already been started
my $nFinished = 0;   #  Num tests that are finsihed
my $nSubmit   = 0;   #  Num tests that were submitted

my $status  = "";
my $details = "";

foreach my $recipe (@recipes) {
    if (-e "$wrkdir/$regr/$recipe/quast/report.txt") {
        $details .= "  Finished: $recipe.\n";
        $nFinished++;
        next;
    }

    if (-e "$wrkdir/$regr/$recipe-submit.sh") {
        $details .= "  Failed:   $recipe.\n";
        $nExist++;
        next;
    }

    my $eerr = 0;
    #print STDERR "SUBMISSION of assembly job DISABLED\n";
    $eerr  = system("cd $wrkdir/$regr && ln -s ../recipes/$recipe/submit.sh $recipe-submit.sh");
    $eerr += system("cd $wrkdir/$regr && sh $recipe-submit.sh $recipe > $recipe-submit.log 2>&1");
    $nSubmit++;

    if ($eerr) {
        postHeading("FAILED!.");
        postFile(undef, "$wrkdir/$regr/$recipe-submit.log");
    }

    $details .= "  Started:  $recipe.\n";
}

if    (($nFinished == 0) && ($nExist == 0) && ($nSubmit  > 0))  {  $status = "$nSubmit recipes *started* in $regr.\n";  }
elsif (($nFinished  > 0) && ($nExist == 0) && ($nSubmit == 0))  {  $status = "*All complete* in $regr.\n";  }
elsif (($nFinished == 0) && ($nExist  > 0) && ($nSubmit == 0))  {  $status = "All $nExist recipes *crashed* or *running* in $regr.\n";  }
elsif (($nFinished  > 0) && ($nExist  > 0) && ($nSubmit == 0))  {  $status = "Some recipes *finished* ($nFinished), some *crashed* or *running* ($nExist) in $regr.\n";  }
else                                                            {  $status = "$nSubmit recipes *started*, $nExist recipes *running*, $nFinished *finished* in $regr.\n";  }

print "$status";
print "$details\n";

if ($details ne "") {
    postFormattedText(undef, "$status```\n$details```\n");
} else {
    postFormattedText(undef, "$status\n");
}

#
#  RESUBMIT, if requested.
#
if (defined($nextByDate)) {
    open(F, "> submit.sh");
    print F "#!/bin/sh\n";
    print F "\n";
    print F "if [ \"x\$SGE_ROOT\" != \"x\" -a \\\n";
    print F "     -e  \$SGE_ROOT/\$SGE_CELL/common/settings.sh ]; then\n";
    print F "  . \$SGE_ROOT/\$SGE_CELL/common/settings.sh\n";
    print F "fi\n";
    print F "\n";
    print F "perl regression.pl $ropts -schedule $sched -expected $nextByDate\n";
    print F "exit 0\n";
    close(F);

    my $qsub   = `which qsub   2> /dev/null`;   chomp $qsub;
    my $sbatch = `which sbatch 2> /dev/null`;   chomp $sbatch;

    if ((-e $qsub) &&
        (-e $sbatch)) {
        postHeading("*HELP!*  Found both `$qsub` and `$sbatch`!");
    }
    elsif (-e $qsub) {
        #print STDERR "SUBMISSION of next round DISABLED - $ropts -schedule $sched -expected $nextByDate\n";
        system("$qsub -cwd -j y -o /dev/null -a $qat ./submit.sh > ./submit.$$.log 2>&1");
    }
    elsif (-e $sbatch) {
        #print STDERR "SUBMISSION of next round DISABLED - $ropts -schedule $sched -expected $nextByDate\n";
        system("$sbatch -D . -o /dev/null -b $sat -p quick ./submit.sh > ./submit.$$.log 2>&1");
    }
    else {
        postHeading("*HELP!*  Found neither `qsub` nor `sbatch`; don't know how to submit grid jobs.");
    }

    my $job = "no status reported";

    if (-e "./submit.$$.log") {
        open(F, "< ./submit.$$.log");
        while (<F>) {
            chomp;

            if (m/Your\sjob\s(\d+)\s/) {
                $job = $1;
            } else {
                $job = $_;
            }
        }
        close(F);
    }

    print "*Resubmitted* to run at $sat ($job)\n";
    postFormattedText(undef, "*Resubmitted* to run at $sat (job $job).\n");

    unlink "submit.sh";
    unlink "submit.$$.log";
}

exit(0);
