#!/usr/bin/perl

# This script takes a "Borrower export" report from Alice 6.0 and imports it
# into the old_issues and issues tables in a Koha database to record the
# checkouts, both current and historical.
#
# A preprocessing step is needed before running this script:
# you must convert the exported .dat file from UTF-16 to UTF-8.
# $ uconv --remove-signature -f UTF-16LE -t UTF-8 -o checkouts.tsv BOREXB00.dat
#
# You must also copy this script, the borrower TSV file, and the
# /etc/koha/sites/SITE/koha-conf.xml file for the Koha site you're
# importing to, to a directory on the server. You must also give your shell
# user ownership of the koha-conf.xml file.

use strict;
use warnings;

# Koha lib install directory on Debian
use lib '/usr/share/koha/lib';

my ($script_path) = abs_path($0) =~ m/(.*)import_checkouts.pl/i;
$ENV{'KOHA_CONF'} = $script_path . 'koha-conf.xml';

use C4::Context;
use Cwd 'abs_path';
use Data::Dumper;
use DateTime;
use Text::CSV;
use Util::Barcode qw(add_check_digit);

my $num_args = @ARGV;
if ($num_args != 1) {
    print "Usage: import_checkouts.pl <INPUT>\n";
    exit;
}

my %borrowers;
sub get_borrowernumber {
    my $dbh = shift;
    my $patron_barcode = shift;

    if (exists $borrowers{$patron_barcode}) {
        return $borrowers{$patron_barcode};
    }

    my $borrowernumber = 0;
    my $patron_sth = $dbh->prepare("SELECT * FROM borrowers WHERE cardnumber = ?");
    $patron_sth->execute($patron_barcode);

    my $borrower = $patron_sth->fetchrow_hashref;
    if ($borrower) {
        $borrowernumber = $borrower->{'borrowernumber'};
    }

    $borrowers{$patron_barcode} = $borrowernumber;

    return $borrowernumber;
}

my %items;
sub get_itemnumber {
    my $dbh = shift;
    my $item_barcode = shift;

    if (exists $items{$item_barcode}) {
        return $items{$item_barcode};
    }

    my $item_number = 0;

    my $item_sth = $dbh->prepare("SELECT * FROM items WHERE (barcode = ?)");
    $item_sth->execute($item_barcode);

    my $item = $item_sth->fetchrow_hashref;
    if ($item) {
        $item_number = $item->{'itemnumber'};
    }

    $items{$item_barcode} = $item_number;

    return $item_number;
}

my $infile_path = $ARGV[0];

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

open(my $in_fh, "<:encoding(utf8)", $infile_path) or die "$infile_path $!";
$in_csv->column_names($in_csv->getline($in_fh));

my $dbh = C4::Context->dbh;

# The primary key is not AUTO_INCREMENT, so we have to manage it ourselves
my $issue_id = -1;

my $max_id_sth = $dbh->prepare("SELECT MAX(issue_id) AS issue_id FROM old_issues");
$max_id_sth->execute();

my $old_issue = $max_id_sth->fetchrow_hashref;
if ($old_issue) {
    $issue_id = $old_issue->{'issue_id'};
}

# We can't insert the currently checked-out books until we know the max
# issue_id in the old_issues table, so just collect the entries as we
# go through the file.
my @current_checkouts;

# Collect "special account" items so we can set the DAMAGED and MISSING
# status in the item information.
my @replacements;
my @repairs;
my @missing_books;
use constant REPLACE_USER_BARCODE => "B01276P4025";
use constant REPAIR_USER_BARCODE => "B00900Y4025";
use constant MISSING_USER_BARCODE => "B02185P4025";

# Collect the total number of times each item has been checked out and, when
# the item was last in the library, and if currently checked out, the due date.
my %times_issued;
my %datelastseen;
my %current_onloan_date;

print "Importing old checkouts...\n";

my $last_barcode = "";

while (my $row = $in_csv->getline_hr($in_fh)) {
    $issue_id++;
    my $patron_barcode = add_check_digit($row->{'Borr barcode'});
    my $item_barcode = add_check_digit($row->{Barcode});

    my $borrowernumber = get_borrowernumber($dbh, $patron_barcode);
    if ($borrowernumber == 0) {
        next;
    }

    my $item_number = get_itemnumber($dbh, $item_barcode);
    if ($item_number == 0) {
        next;
    }

    my $loan_date = $row->{'Loan date'};
    my $due_date = $row->{'Due date'};
    my $returned_date = $row->{'Returned'};
    my $last_renewal_date;
    my $num_renewals = $row->{'Renewed'} + 0;

    # Convert date to ISO format
    $loan_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;
    $due_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;

    if (!exists $datelastseen{$item_number} || $loan_date gt $datelastseen{$item_number}) {
        $datelastseen{$item_number} = $loan_date;
    }

    # If renewed, calculate the last renewal date
    if ($num_renewals > 0 && $due_date =~ /(\d\d\d\d)-(\d\d)-(\d\d)/) {
        my $last_renewal_datetime = DateTime->new(
            year   => $1,
            month  => $2,
            day    => $3,
            hour   => 14,
            minute => 0,
            second => 0
        );

        $last_renewal_datetime->add(days => -28);
        $last_renewal_date = $last_renewal_datetime->ymd . ' ' .
            $last_renewal_datetime->hms;
    }

    # Koha stores NULL instead of 0 if there have been no renewals
    if ($num_renewals == 0) {
        undef $num_renewals;
    }

    # Add a time to each date
    $loan_date .= " 12:00:00";
    $due_date .= " 23:59:59";

    if ($returned_date eq "  /  /    ") {
        # This item has not yet been returned
        if ($patron_barcode eq REPAIR_USER_BARCODE) {
            push @repairs, $item_number;
            next;
        } elsif ($patron_barcode eq REPLACE_USER_BARCODE) {
            push @replacements, $item_number;
            next;
        } elsif ($patron_barcode eq MISSING_USER_BARCODE) {
            push @missing_books, $item_number;
            next;
        }

        push @current_checkouts, {
            'borrowernumber' => $borrowernumber,
            'itemnumber' => $item_number,
            'date_due' => $due_date,
            'lastreneweddate' => $last_renewal_date,
            'renewals' => $num_renewals,
            'issuedate' => $loan_date,
        };

        my $onloan_date = substr($due_date, 0, 10);
        $current_onloan_date{$item_number} = $onloan_date;
    } else {
        # Convert date to ISO format
        $returned_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;

        # Add a time to the returned date
        $returned_date .= " 14:00:00";

        my $query = "
            INSERT INTO old_issues
            (issue_id, borrowernumber, itemnumber, date_due, branchcode, returndate, lastreneweddate, renewals, auto_renew, timestamp, issuedate, onsite_checkout)
            VALUES
            (?, ?, ?, ?, 'IELD', ?, ?, ?, 0, ?, ?, 0)";
        my $insert_sth = $dbh->prepare($query);
        $insert_sth->execute(
            $issue_id,
            $borrowernumber,
            $item_number,
            $due_date,
            $returned_date,
            $last_renewal_date,
            $num_renewals,
            $returned_date,
            $loan_date
        );
    }

    # Do this at the end in case the item was checked out to a "special" patron
    if (exists $times_issued{$item_number}) {
        $times_issued{$item_number}++;
    } else {
        $times_issued{$item_number} = 1;
    }
}

# Since the issue_id values get transferred from issues to old_issues, we
# have to make sure none of the rows in the issues table shares an ID
# with a row in the old_issues table.
my $issues_auto_inc = $issue_id + 1;
my $alter_sth = $dbh->prepare("ALTER TABLE issues AUTO_INCREMENT = " . $issues_auto_inc);
$alter_sth->execute();

print "Importing current checkouts...\n";
for my $checkout (@current_checkouts) {
    my $query = "
        INSERT INTO issues
        (borrowernumber, itemnumber, date_due, branchcode, lastreneweddate, renewals, auto_renew, timestamp, issuedate, onsite_checkout)
        VALUES
        (?, ?, ?, 'IELD', ?, ?, 0, ?, ?, 0)";
    my $insert_sth = $dbh->prepare($query);
    $insert_sth->execute(
        $checkout->{borrowernumber},
        $checkout->{itemnumber},
        $checkout->{date_due},
        $checkout->{lastreneweddate},
        $checkout->{renewals},
        $checkout->{issuedate},
        $checkout->{issuedate}
    );
}

print "Updating items...\n";
keys %times_issued;
while(my($item_number, $num_issues) = each %times_issued) {
    if (exists $current_onloan_date{$item_number}) {
        my $item_update_sth = $dbh->prepare("UPDATE items SET issues = ?, onloan = ?, datelastseen = ? WHERE itemnumber = ?");
        $item_update_sth->execute($num_issues, $current_onloan_date{$item_number}, $datelastseen{$item_number}, $item_number);
    } else {
        my $item_update_sth = $dbh->prepare("UPDATE items SET issues = ?, datelastseen = ? WHERE itemnumber = ?");
        $item_update_sth->execute($num_issues, $datelastseen{$item_number}, $item_number);
    }
}

print "Setting item states...\n";
foreach my $item_number (@replacements) {
    my $item_update_sth = $dbh->prepare("UPDATE items SET damaged = ? WHERE itemnumber = ?");
    $item_update_sth->execute(2, $item_number);
}

foreach my $item_number (@repairs) {
    my $item_update_sth = $dbh->prepare("UPDATE items SET damaged = ? WHERE itemnumber = ?");
    $item_update_sth->execute(1, $item_number);
}

foreach my $item_number (@missing_books) {
    my $item_update_sth = $dbh->prepare("UPDATE items SET itemlost = ? WHERE itemnumber = ?");
    $item_update_sth->execute(2, $item_number);
}

print "Import done.\n";
