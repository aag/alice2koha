#!/usr/bin/perl

# This script takes a "Fine Statistics" report from Alice 6.0 and imports it
# into the accountlines table in a Koha database to record the current fines.
#
# A preprocessing step is needed before running this script:
# you must convert the exported .dat file from UTF-16 to UTF-8.
# $ iconv -f UTF-16LE -t UTF-8 -o fines.txt FSTATR00.txt

use strict;
use warnings;

use Util::Barcode qw(add_check_digit);

my $num_args = @ARGV;
if ($num_args != 1) {
    print "Usage: import_fines.pl <INPUT>\n";
    exit;
}

my $infile_path = $ARGV[0];

open(my $in_fh, $infile_path) or die "Could not open $infile_path: $!";

while (my $line = <$in_fh>) {
    chomp $line;

    # Throw out lines that don't start with a patron's barcode
    if (!($line =~ /^B\d+    /)) {
        next;
    }

    if ($line =~ /^(B\d+).*    (R\d+)      .*0\.00       (\d+\.\d+)\s+(\d\d\/\d\d\/\d\d\d\d)/) {
        # This is an overdue fine
        my $patron_barcode = add_check_digit($1);
        my $biblio_barcode = add_check_digit($2);
        my $fine_amount = $3;
        my $fine_date = $4;

        # Convert date to ISO format
        $fine_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;

        print "Overdue charge: $patron_barcode\t$biblio_barcode\t$fine_amount\t$fine_date\n";
    } elsif ($line =~ /^(B\d+)    .*0\.00       (\d+\.\d+)\s+(\d\d\/\d\d\/\d\d\d\d)/) {
        # This is a membership fee
        my $patron_barcode = add_check_digit($1);
        my $fee_amount = $2;
        my $fee_date = $3;

        # Convert date to ISO format
        $fee_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;

        print "Membership charge: $patron_barcode\t$fee_amount\t$fee_date\n";
    }
}

close($in_fh);

