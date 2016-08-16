#!/usr/bin/perl

# This script takes the "Borrower Details Export" in the
# "Text file - Unicode (.txt)" format from Alice 6.0 and imports the date of
# birth into the borrowers table in Koha.
#
# This script might be needed if you ran convert_users.pl before the date
# format was changed to ISO format and you had a different date format
# configured in Koha when you imported the users.
#
# A preprocessing step is needed before running this script:
# you must convert the exported .dat file from UTF-16 to UTF-8.
# $ iconv -f UTF-16LE -t UTF-8 -o borrowers.tsv BORRWB00.dat
#
# You must also copy this script, the fines text file, and the
# /etc/koha/sites/SITE/koha-conf.xml file for the Koha site you're
# importing to, to a directory on the server. You must also give your shell
# user ownership of the koha-conf.xml file.

use strict;
use warnings;

# Koha lib install directory on Debian
use lib '/usr/share/koha/lib';

my ($script_path) = abs_path($0) =~ m/(.*)import_dateofbirth.pl/i;
$ENV{'KOHA_CONF'} = $script_path . 'koha-conf.xml';

use C4::Context;
use Cwd 'abs_path';
use Text::CSV;
use Util::Barcode qw(add_check_digit);

my $num_args = @ARGV;
if ($num_args != 1) {
    print "Usage: import_dateofbirth.pl <INPUT>\n";
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

my $input_path = $ARGV[0];

my $in_csv = Text::CSV->new({
    binary => 1,
    quote_char => undef,
    escape_char => undef,
    quote_space => 0,
    quote_null => 0,
    sep_char => "\t",
    allow_loose_quotes => 1,
    allow_loose_escapes => 1,
}) or die "Cannot use CSV: " . Text::CSV->error_diag();

my $dbh = C4::Context->dbh;

open(my $in_fh, "<:encoding(utf8)", $input_path) or die "$input_path: $!";
$in_csv->column_names($in_csv->getline($in_fh));

while (my $row = $in_csv->getline_hr($in_fh)) {
    $row->{Barcode} =~ m/^B/ or next; # Exclude old-style borrower IDs

    my $patron_barcode = add_check_digit($row->{Barcode});

    my $borrowernumber = get_borrowernumber($dbh, $patron_barcode);
    if ($borrowernumber == 0) {
        next;
    }

    # There are 5 different fields which might contain the DOB
    my @dob_fields = (
        "Date Of Birth (DOB)",
        "User defined field 2",
        "User defined field 3",
        "User defined field 6",
        "User defined field 7",
    );

    my $dob = "";
    foreach my $field (@dob_fields) {
        # Try to parse various formats like 01.01.1999, 1/1/99, 01,1,1999
        if ($row->{$field} =~ /^(\d?\d)\D(\d?\d)\D(\d\d|\d\d\d\d)$/) {
            my $day = $1;
            my $month = $2;
            my $year = $3;

            if (length $year == 2) {
                $year = "19$year";
            }

            if (length $month == 1) {
                $month = "0$month";
            }

            if (length $day == 1) {
                $day = "0$day";
            }

            $dob = "$year-$month-$day";

            last;
        }
    }

    if (length $dob == 0) {
        print "$borrowernumber - $patron_barcode - $dob\n";
    }

    my $query = "
        UPDATE borrowers
        SET dateofbirth=?
        WHERE borrowernumber=?";
    my $insert_sth = $dbh->prepare($query);
    $insert_sth->execute($dob, $borrowernumber);
}

close($in_fh);
