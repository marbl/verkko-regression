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
