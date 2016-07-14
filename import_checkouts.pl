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
    print "Usage: import_fines.pl <INPUT>\n";
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

my $infile_path = $ARGV[0];

my $in_csv = Text::CSV->new({
    binary => 1,
    quote_char => '¸',
    escape_char => "\\",
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

while (my $row = $in_csv->getline_hr($in_fh)) {
    $issue_id++;
    my $patron_barcode = add_check_digit($row->{'Borr barcode'});
    my $biblio_barcode = add_check_digit($row->{Barcode});

    my $borrowernumber = get_borrowernumber($dbh, $patron_barcode);
    if ($borrowernumber == 0) {
        next;
    }

    my $item_sth = $dbh->prepare("SELECT * FROM items WHERE (barcode = ?)");
    $item_sth->execute($biblio_barcode);

    my $item = $item_sth->fetchrow_hashref;
    if ($item) {
        my $item_number = $item->{'itemnumber'};

        my $loan_date = $row->{'Loan date'};
        my $due_date = $row->{'Due date'};
        my $returned_date = $row->{'Returned'};
        my $last_renewal_date;
        my $num_renewals = $row->{'Renewed'} + 0;

        # Convert date to ISO format
        $loan_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;
        $due_date =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/;

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

        # Get the number of issues for item
        #my $item_issues_sth = $dbh->prepare("SELECT issues FROM items WHERE itemnumber = ?");
        #$item_issues_sth->execute($item_number);

        #my $item = $item_issues_sth->fetchrow_hashref;
        #my $num_issues = 1;
        #if ($item) {
            #my $db_num_issues = $item->{'issues'};
            #if ($db_num_issues) {
                #$num_issues = $db_num_issues + 1;
            #}
        #}

        # Add a time to each date
        $loan_date .= " 12:00:00";
        $due_date .= " 23:59:59";

        if ($returned_date eq "  /  /    ") {
            # This item has not yet been returned
            push @current_checkouts, {
                'borrowernumber' => $borrowernumber,
                'itemnumber' => $item_number,
                'date_due' => $due_date,
                'lastreneweddate' => $last_renewal_date,
                'renewals' => $num_renewals,
                'issuedate' => $loan_date,
            };

            #my $onloan_date = substr($due_date, 0, 10);

            #my $item_update_sth = $dbh->prepare("UPDATE items SET issues=?, onloan=?");
            #$item_update_sth->execute($num_issues, $onloan_date);
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

            #my $item_update_sth = $dbh->prepare("UPDATE items SET issues=?");
            #$item_update_sth->execute($num_issues);
        }

        print("borrower: " . $row->{'Borr barcode'} .
            " ($borrowernumber), item: " . $row->{Barcode} .
            " ($item_number), Loan date: $loan_date, Due date: $due_date, " .
            "Returned: $returned_date\n");
    }
}

# Since the issue_id values get transferred from issues to old_issues, we
# have to make sure none of the rows in the issues table shares an ID
# with a row in the old_issues table.
my $issues_auto_inc = $issue_id + 1;
my $alter_sth = $dbh->prepare("ALTER TABLE issues AUTO_INCREMENT = ?");
$alter_sth->execute($issues_auto_inc);

# print Dumper(\@current_checkouts);

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


