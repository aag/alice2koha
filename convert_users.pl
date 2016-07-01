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
# TODO: Record country of origin
# TODO: make exclusions and categories configurable

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

binmode(STDOUT, ":utf8");

# Takes several address fields from the Alice export and
# attempts to parse out a structured address from them.
sub parse_address {
    my ($street_num, $street_name, $addr_1, $addr_2, $addr_3, $postcode) = @_;

    my $out_street_name = "";
    my $out_street_num = "";
    my $out_postcode = "";
    my $out_city = "";
    my $out_addr_2 = "";

    if ($street_num eq "" && $addr_3 eq "" &&
        (($addr_1 eq "" && $addr_2 =~ /(\d\d\d\d\d )?\w+$/) ||
            ($addr_2 eq "" && $addr_1 =~ /(\d\d\d\d\d )?\w+$/)) &&
        ($postcode eq "" || $postcode =~ /^\d\d\d\d\d$/)) {
        # This is the most common case. The street name and number is in
        # $street_name and the postcode and city are in $addr_1 or $addr_2
        if ($street_name =~ /(\D+) ?(\d+.*)$/) {
            $out_street_name = $1;
            $out_street_num = $2;
            $out_street_num =~ s/,$//;
        }

        my $postcode_city = $addr_1;
        if ($postcode_city eq "") {
            $postcode_city = $addr_2;
        }

        if ($postcode_city =~ /(\d\d\d\d\d) +(\w+.*)$/) {
            $out_postcode = $1;
            $out_city = $2;
        } elsif ($postcode =~ /\d\d\d\d\d/) {
            $out_postcode = $postcode;
            $out_city = $postcode_city;
        } elsif ($postcode_city =~ /^\w+$/) {
            $out_city = $postcode_city;
        }
    } elsif ($street_num =~ /^\D+$/ && $street_name =~ /^\d+/ &&
        $addr_3 eq "" &&
        (($addr_1 eq "" && $addr_2 =~ /(\d\d\d\d\d )?\w+$/) ||
            ($addr_2 eq "" && $addr_1 =~ /(\d\d\d\d\d )?\w+$/)) &&
        ($postcode eq "" || $postcode =~ /^\d\d\d\d\d$/)) {
        # In this case, Alice managed to correctly identify the street
        # name and number, but they are stored in the opposite fields as
        # labeled, since the order is opposite in German and English.
        $out_street_name = $street_num;
        $out_street_num = $street_name;
        $out_street_num =~ s/,$//;

        my $postcode_city = $addr_1;
        if ($postcode_city eq "") {
            $postcode_city = $addr_2;
        }

        if ($postcode_city =~ /(\d\d\d\d\d) +(\w+.*)$/) {
            $out_postcode = $1;
            $out_city = $2;
        } elsif ($postcode =~ /\d\d\d\d\d/) {
            $out_postcode = $postcode;
            $out_city = $postcode_city;
        } elsif ($postcode_city =~ /^\w+$/) {
            $out_city = $postcode_city;
        }
    } elsif ($street_num =~ /^\D+$/ && $street_name =~ /^\D+\d+/ &&
        $addr_3 eq "" &&
        (($addr_1 eq "" && $addr_2 =~ /(\d\d\d\d\d )?\w+$/) ||
            ($addr_2 eq "" && $addr_1 =~ /(\d\d\d\d\d )?\w+$/)) &&
        ($postcode eq "" || $postcode =~ /^\d\d\d\d\d$/)) {
        # In this case, Alice split up the street name across $street_num
        # and $street_name. Sometimes it does it in the middle of a word and
        # sometimes between words. We use the capitalization of the first
        # letter and some known starting word in $street_name to try to figure
        # out if the split happened between words or not.
        my $street_addr = $street_num . $street_name;
        if ($street_name =~ /^[[:upper:]]/ || $street_name =~ /^(dem|der) /) {
            $street_addr = $street_num . " " . $street_name;
        }

        if ($street_addr =~ /(\D+) ?(\d+.*)$/) {
            $out_street_name = $1;
            $out_street_num = $2;
            $out_street_num =~ s/,$//;
        } 

        my $postcode_city = $addr_1;
        if ($postcode_city eq "") {
            $postcode_city = $addr_2;
        }

        if ($postcode_city =~ /(\d\d\d\d\d) +(\w+.*)$/) {
            $out_postcode = $1;
            $out_city = $2;
        } elsif ($postcode =~ /\d\d\d\d\d/) {
            $out_postcode = $postcode;
            $out_city = $postcode_city;
        } elsif ($postcode_city =~ /^\w+$/) {
            $out_city = $postcode_city;
        } 
    } elsif ($street_num eq "c/o" && $street_name ne "" &&
        $addr_1 ne "" && $addr_2 =~ /\d\d\d\d\d \w+$/) {
        # There's a "care of" line
        $out_addr_2 = "c/o $street_name";

        if ($addr_1 =~ /(\D+) ?(\d+.*)$/) {
            $out_street_name = $1;
            $out_street_num = $2;
            $out_street_num =~ s/,$//;
        }

        if ($addr_2 =~ /(\d\d\d\d\d) +(\w+.*)$/) {
            $out_postcode = $1;
            $out_city = $2;
        }
    }

    return (
        "street_name" => $out_street_name,
        "street_num" => $out_street_num,
        "postcode" => $out_postcode,
        "city" => $out_city,
        "address2" => $out_addr_2,
    );
}


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

    # There are 4 different fields which might contain the DOB
    my @dob_fields = (
        "Date Of Birth (DOB)",
        "User defined field 2",
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

            $dob = "$day-$month-$year";

            last;
        }
    }

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

    my %address = parse_address(
        $row->{"Street Number"},
        $row->{"Street Name"},
        $row->{"Address Line 1"},
        $row->{"Address Line 2"},
        $row->{"Address Line 3"},
        $row->{"Postcode"},
    );

    # Uncomment to output unparseable addresses
    #if ($address{'street_num'} eq "" || $address{'street_name'} eq "" ||
        #$address{'city'} eq "" || $address{'postcode'} eq "") {
        #print($row->{Barcode} . ": " . $row->{Surname} .
            #", " . $row->{"Given name"} . "\n");
    #}

    my @out_row = [
        $row->{Barcode}, # cardnumber
        $row->{Surname}, # surname
        $row->{"Given name"}, # firstname
        $row->{"Mailing title"}, # title
        "", # othernames
        "", # initials
        $address{'street_num'}, # streetnumber
        "", # streettype
        $address{'street_name'}, # address
        $address{'address2'}, # address2
        $address{'city'}, # city
        "", # state
        $address{'postcode'}, # zipcode
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

