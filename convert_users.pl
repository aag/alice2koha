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

my $numArgs = @ARGV;
if ($numArgs != 2) {
    print "Usage: convert_users.pl <INPUT> <OUTPUT>\n";
    exit;
}

my $inputPath = $ARGV[0];
my $outputPath = $ARGV[1];

my $inCsv = Text::CSV->new({
    binary => 1,
}) or die "Cannot use CSV: " . Text::CSV->error_diag();

my $outCsv = Text::CSV->new({
    binary => 1,
}) or die "Cannot use CSV: " . Text::CSV->error_diag();

$outCsv->eol("\n");

open my $inFileHandle, "<:encoding(utf8)", $inputPath or die "$inputPath: $!";
open my $outFileHandle, ">:encoding(utf8)", $outputPath or die "$outputPath: $!";

$inCsv->column_names($inCsv->getline($inFileHandle));

my @headerRow = qw(cardnumber surname firstname title othernames initials streetnumber streettype address address2 city state zipcode country email phone mobile fax emailpro phonepro B_streetnumber B_streettype B_address B_address2 B_city B_state B_zipcode B_country B_email B_phone dateofbirth branchcode categorycode dateenrolled dateexpiry gonenoaddress lost debarred debarredcomment contactname contactfirstname contacttitle guarantorid borrowernotes relationship ethnicity ethnotes sex password flags userid opacnote contactnote sort1 sort2 altcontactfirstname altcontactsurname altcontactaddress1 altcontactaddress2 altcontactaddress3 altcontactstate altcontactzipcode altcontactcountry altcontactphone smsalertnumber privacy patron_attributes);
$outCsv->print($outFileHandle, \@headerRow);

while (my $row = $inCsv->getline_hr($inFileHandle)) {
    $row->{Barcode} =~ m/^B/ or next; # Exclude old-style borrower IDs
    $row->{"Membership expiry date"} =~ m/2016|2017/ or next;

    my $dob = $row->{"Date Of Birth (DOB)"};
    if ($dob eq "/  /" or $dob eq "") {
        $dob = $row->{"User defined field 2"};
    }

    my @outRow = [
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
        "", # branchcode
        "", # categorycode
        $row->{"Membership Start Date"}, # dateenrolled
        $row->{"Membership expiry date"}, # dateexpiry
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
        $row->{"User defined field 1"}, # ethnicity
        "", # ethnotes
        $row->{Sex}, # sex
        "", # password
        "", # flags
        "", # userid
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
        "", # patron_attributes
    ];
    $outCsv->print($outFileHandle, @outRow);
}
$inCsv->eof or $inCsv->error_diag();

close $inFileHandle or die "$outputPath: $!";
close $outFileHandle or die "$outputPath: $!";

