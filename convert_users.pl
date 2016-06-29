#!/usr/bin/perl

# This script takes the "Borrowers Detail Export" in the
# "Text file - Unicode (.txt)" format from Alice 6.0 and
# converts it to a patrons import file for Koha 3.22.
#
# A preprocessing step is needed before running this script:
# you must convert the exported .dat file from UTF-16 to UTF-8.
# $ iconv -f UTF-16LE -t UTF-8 -o BORRWB00.tsv BORRWB00.dat
#
# Additionally, you must set up the Patron categories in the
# Koha administration interface, which can be reached under
# "Administration" -> "Patron categories".
#
# TODO: parse address into structured fields
# TODO: combine all comment fields and write them to borrowernotes

use strict;
use warnings;

use Text::CSV;

use Data::Dumper;

my $num_args = @ARGV;
if ($num_args != 2) {
    print "Usage: convert_users.pl <INPUT> <OUTPUT>\n";
    exit;
}

my $input_path = $ARGV[0];
my $output_path = $ARGV[1];

my $in_csv = Text::CSV->new({
    binary => 1,
    quote_char => '¸',
    escape_char => "\\",
    sep_char => "\t",
    allow_loose_quotes => 1,
    allow_loose_escapes => 1,
}) or die "Cannot use CSV: " . Text::CSV->error_diag();

my $out_csv = Text::CSV->new({
    binary => 1,
}) or die "Cannot use CSV: " . Text::CSV->error_diag();

$out_csv->eol("\n");

open(my $in_fh, "<:encoding(utf8)", $input_path) or die "$input_path: $!";
open(my $out_fh, ">:encoding(utf8)", $output_path) or die "$output_path: $!";

$in_csv->column_names($in_csv->getline($in_fh));

my @header_row = qw(cardnumber surname firstname title othernames initials streetnumber streettype address address2 city state zipcode country email phone mobile fax emailpro phonepro B_streetnumber B_streettype B_address B_address2 B_city B_state B_zipcode B_country B_email B_phone dateofbirth branchcode categorycode dateenrolled dateexpiry gonenoaddress lost debarred debarredcomment contactname contactfirstname contacttitle guarantorid borrowernotes relationship sex password flags userid opacnote contactnote sort1 sort2 altcontactfirstname altcontactsurname altcontactaddress1 altcontactaddress2 altcontactaddress3 altcontactstate altcontactzipcode altcontactcountry altcontactphone smsalertnumber privacy);
$out_csv->print($out_fh, \@header_row);

my $member_count = 0;
while (my $row = $in_csv->getline_hr($in_fh)) {
    $row->{Barcode} =~ m/^B/ or next; # Exclude old-style borrower IDs
    
    # Uncomment this line to exclude expired memberships
    #$row->{"Membership expiry date"} =~ m/2016|2017|2018|2019|2020/ or next;

    my $dob = $row->{"Date Of Birth (DOB)"};
    if ($dob eq "/  /" or $dob eq "") {
        $dob = $row->{"User defined field 2"};
    }

    $dob =~ s/\//-/g;

    my $patron_category = "N";
    my $alice_category = $row->{"User Loan Category"};
    if ($alice_category eq "reduced") {
        $patron_category = "R";
    } elsif ($alice_category =~ /Volunteer/) {
        $patron_category = "V";
    } elsif ($alice_category eq "VHS Teacher or Hon.") {
        $patron_category = "VHS";
    }

    my $debarred = "";
    if ($alice_category =~ "Banned") {
        $debarred = "9999-12-31";
    }

    my $date_enrolled = $row->{"Membership Start Date"};
    $date_enrolled =~ s/\//-/g;
    my $date_expiry = $row->{"Membership expiry date"};
    $date_expiry =~ s/\//-/g;

    my $username = lc($row->{"Given name"} . $row->{Surname});
    $username =~ s/[ \(\)!-\.\+]//g;

    my $address = $row->{"Street Number"};
    if ($row->{"Street Name"}) {
        $address .= " " . $row->{"Street Name"};
    }

    if ($row->{"Address Line 1"}) {
        $address .= " " . $row->{"Address Line 1"};
    }

    if ($row->{"Address Line 2"}) {
        $address .= " " . $row->{"Address Line 2"};
    }

    # Trim whitespace around the address
    $address =~ s/^\s+|\s+$//g;

    my @out_row = [
        $row->{Barcode}, # cardnumber
        $row->{Surname}, # surname
        $row->{"Given name"}, # firstname
        $row->{"Mailing title"}, # title
        "", # othernames
        "", # initials
        "", # streetnumber
        "", # streettype
        $address, # address
        "", # address2
        "", # city
        "", # state
        $row->{Postcode}, # zipcode
        "", # country
        $row->{Email}, # email
        $row->{"Home Phone"}, # phone
        $row->{"Mobile Phone"}, # mobile
        "", # fax
        "", # emailpro
        $row->{"Work phone"}, # phonepro
        "", # B_streetnumber
        "", # B_streettype
        "", # B_address
        "", # B_address2
        "", # B_city
        "", # B_state
        "", # B_zipcode
        "", # B_country
        "", # B_email
        "", # B_phone
        $dob, # dateofbirth
        "IELD", # branchcode
        $patron_category, # categorycode
        $date_enrolled, # dateenrolled
        $date_expiry, # dateexpiry
        "", # gonenoaddress
        "", # lost
        $debarred, # debarred
        "", # debarredcomment
        "", # contactname
        "", # contactfirstname
        "", # contacttitle
        "", # guarantorid
        "", # borrowernotes
        "", # relationship
        $row->{Sex}, # sex
        "demopatron", # password
        "", # flags
        $username, # userid
        "", # opacnote
        "", # contactnote
        "", # sort1
        "", # sort2
        "", # altcontactfirstname 
        "", # altcontactsurname
        "", # altcontactaddress1
        "", # altcontactaddress2
        "", # altcontactaddress3
        "", # altcontactstate
        "", # altcontactzipcode
        "", # altcontactcountry
        "", # altcontactphone
        "", # smsalertnumber
        "", # privacy
    ];
    $out_csv->print($out_fh, @out_row);
    $member_count += 1;
}
$in_csv->eof or $in_csv->error_diag();

close($in_fh) or die "$output_path: $!";
close($out_fh) or die "$output_path: $!";

print("Member count: $member_count\n");

