#!/usr/bin/perl

# This script takes a "Fine Statistics" report from Alice 6.0 and imports it
# into the accountlines table in a Koha database to record the current fines.
#
# The report can be exported by opening Alice, going to “Alice 6.00” ->
# “Circulation” -> “Reports” -> “Fine statistics”, then choosing
# “01 Fine Statistics” from the dropdown.
#
# A preprocessing step is needed before running this script:
# you must convert the exported .dat file from UTF-16 to UTF-8.
# $ iconv -f UTF-16LE -t UTF-8 -o fines.txt FSTATR00.txt
#
# You must also copy this script, the fines text file, and the
# /etc/koha/sites/SITE/koha-conf.xml file for the Koha site you're
# importing to, to a directory on the server. You must also give your shell
# user ownership of the koha-conf.xml file.

use strict;
use warnings;

# Koha lib install directory on Debian
use lib '/usr/share/koha/lib';

my ($script_path) = abs_path($0) =~ m/(.*)import_fines.pl/i;
$ENV{'KOHA_CONF'} = $script_path . 'koha-conf.xml';

use C4::Context;
use Cwd 'abs_path';
use Util::Barcode qw(add_check_digit);

my $num_args = @ARGV;
if ($num_args != 1) {
    print "Usage: import_fines.pl <INPUT>\n";
    exit;
}

sub get_borrowernumber {
    my $dbh = shift;
    my $patron_barcode = shift;

    my $borrowernumber = 0;
    my $patron_sth = $dbh->prepare("SELECT * FROM borrowers WHERE cardnumber = ?");
    $patron_sth->execute($patron_barcode);

    my $borrower = $patron_sth->fetchrow_hashref;
    if ($borrower) {
        $borrowernumber = $borrower->{'borrowernumber'};
    }

    return $borrowernumber;
}

my $infile_path = $ARGV[0];

open(my $in_fh, $infile_path) or die "Could not open $infile_path: $!";
my $dbh = C4::Context->dbh;

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

        my $borrowernumber = get_borrowernumber($dbh, $patron_barcode);
        if ($borrowernumber == 0) {
            next;
        }

        # Convert date to ISO format
        $fine_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;

        my $sth = $dbh->prepare("SELECT * FROM items WHERE (barcode = ?)");
        $sth->execute($biblio_barcode);

        my $item = $sth->fetchrow_hashref;
        if ($item) {
            my $item_number = $item->{'itemnumber'};
            my $description = "overdue book $item_number";

            #print("itemnumber: $item_number barcode: " . $item->{'barcode'} . " borrowernumber: $borrowernumber barcode: $patron_barcode\n");
            print("Overdue charge: $patron_barcode\t$biblio_barcode\t$fine_amount\t$fine_date\n");

            my $query = "
                INSERT INTO accountlines
                (borrowernumber, itemnumber, date, amount, description, accounttype, amountoutstanding, timestamp, notify_id, notify_level, manager_id)
                VALUES
                (?, ?, ?, ?, ?, 'F', ?, ?, 1, 0, 1)";
            my $insert_sth = $dbh->prepare($query);
            $insert_sth->execute($borrowernumber, $item_number, $fine_date, $fine_amount, $description, $fine_amount, "$fine_date 12:00:00");
        }

    } elsif ($line =~ /^(B\d+)    .*0\.00       (\d+\.\d+)\s+(\d\d\/\d\d\/\d\d\d\d)/) {
        # This is a membership fee
        my $patron_barcode = add_check_digit($1);
        my $fine_amount = $2;
        my $fine_date = $3;

        my $borrowernumber = get_borrowernumber($dbh, $patron_barcode);
        if ($borrowernumber == 0) {
            next;
        }

        # Convert date to ISO format
        $fine_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;

        print "Membership charge: $patron_barcode\t$fine_amount\t$fine_date\n";

        my $query = "
                INSERT INTO accountlines
                (borrowernumber, date, amount, description, accounttype, amountoutstanding, timestamp, notify_id, notify_level, manager_id)
                VALUES
                (?, ?, ?, '', 'A', ?, ?, 1, 0, 1)";
            my $insert_sth = $dbh->prepare($query);
            $insert_sth->execute($borrowernumber, $fine_date, $fine_amount, $fine_amount, "$fine_date 12:00:00");
    }
}

close($in_fh);
