#!/usr/bin/perl

# This script takes the "Borrowers Detail Export" from Alice 6.0 and
# converts it to a patrons import file for Koha 3.22.
#
# Two preprocessing steps are needed before running this script:
# 1. Convert the exported tsv file from UTF-16 to UTF-8.
# 2. Convert the tsv file to csv (e.g. with Gnumeric).

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
}) or die "Cannot use CSV: " . Text::CSV->error_diag();

my $out_csv = Text::CSV->new({
    binary => 1,
}) or die "Cannot use CSV: " . Text::CSV->error_diag();

$out_csv->eol("\n");

open my $in_file_handle, "<:encoding(utf8)", $input_path or die "$input_path: $!";
open my $out_file_handle, ">:encoding(utf8)", $output_path or die "$output_path: $!";

$in_csv->column_names($in_csv->getline($in_file_handle));

my @header_row = qw(cardnumber surname firstname title othernames initials streetnumber streettype address address2 city state zipcode country email phone mobile fax emailpro phonepro B_streetnumber B_streettype B_address B_address2 B_city B_state B_zipcode B_country B_email B_phone dateofbirth branchcode categorycode dateenrolled dateexpiry gonenoaddress lost debarred debarredcomment contactname contactfirstname contacttitle guarantorid borrowernotes relationship sex password flags userid opacnote contactnote sort1 sort2 altcontactfirstname altcontactsurname altcontactaddress1 altcontactaddress2 altcontactaddress3 altcontactstate altcontactzipcode altcontactcountry altcontactphone smsalertnumber privacy);
$out_csv->print($out_file_handle, \@header_row);

while (my $row = $in_csv->getline_hr($in_file_handle)) {
    $row->{Barcode} =~ m/^B/ or next; # Exclude old-style borrower IDs
    $row->{"Membership expiry date"} =~ m/2016|2017/ or next;

    my $dob = $row->{"Date Of Birth (DOB)"};
    if ($dob eq "/  /" or $dob eq "") {
        $dob = $row->{"User defined field 2"};
    }

    $dob =~ s/\//-/g;

    my $patron_category = "N";
    my $alice_catgory = $row->{"User Loan Category"};
    if ($alice_catgory eq "reduced") {
        $patron_category = "R";
    } elsif ($alice_catgory =~ /Volunteer/) {
        $patron_category = "V";
    } elsif ($alice_catgory eq "VHS Teacher or Hon.") {
        $patron_category = "VHS";
    }

    my $date_enrolled = $row->{"Membership Start Date"};
    $date_enrolled =~ s/\//-/g;
    my $date_expiry = $row->{"Membership expiry date"};
    $date_expiry =~ s/\//-/g;

    my $username = lc($row->{"Given name"} . $row->{Surname});
    $username =~ s/[ \(\)!-\.\+]//g;

    my @out_row = [
        $row->{Barcode}, # cardnumber
        $row->{Surname}, # surname
        $row->{"Given name"}, # firstname
        $row->{"Mailing title"}, # title
        "", # othernames
        "", # initials
        $row->{"Street Number"}, # streetnumber
        $row->{"Street Name"}, # streettype
        $row->{"Address Line 1"}, # address
        $row->{"Address Line 2"}, # address2
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
        "", # debarred
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
    $out_csv->print($out_file_handle, @out_row);
}
$in_csv->eof or $in_csv->error_diag();

close $in_file_handle or die "$output_path: $!";
close $out_file_handle or die "$output_path: $!";

