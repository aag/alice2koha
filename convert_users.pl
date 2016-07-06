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
# TODO: make exclusions and categories configurable

use strict;
use warnings;

use lib '.';

use Data::Dumper;
use Text::CSV;
use Util::Barcode qw(add_check_digit);

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

my %countries = (
    'Algerian' => 'Algeria',
    'american' => 'United States of America',
    'America' => 'United States of America',
    'American' => 'United States of America',
    'Ameican' => 'United States of America',
    'Australia' => 'Australia',
    'australian' => 'Australia',
    'Australian' => 'Australia',
    'Austrian' => 'Austria',
    'Bahamian' => 'Bahamas',
    'Bangladeshi' => 'Bangladesh',
    'Belarus' => 'Belarus',
    'Belgian' => 'Belgium',
    'Botswana' => 'Botswana',
    'Brasilian' => 'Brazil',
    'Brazil' => 'Brazil',
    'Brazilian' => 'Brazil',
    'British' => 'United Kingdom',
    'Britisch' => 'United Kingdom',
    'bulgarian' => 'Bulgaria',
    'Bulgarian' => 'Bulgaria',
    'canadian' => 'Canadia',
    'Canadian' => 'Canadia',
    'Chilean' => 'Chile',
    'Chinese' => 'China',
    'Congolesian' => 'Congo, Democratic Republic of the',
    'Croatia' => 'Croatia',
    'Croatian' => 'Croatia',
    'Czech' => 'Czech Republic',
    'Danish' => 'Denmark',
    'Danmark' => 'Denmark',
    'Denmark' => 'Denmark',
    'deutsch' => 'Germany',
    'Deutsch' => 'Germany',
    'Dutch' => 'Netherlands',
    'Ecuadorian' => 'Ecuador',
    'Egypt' => 'Egypt',
    'Egyptian' => 'Egypt',
    'Eire' => 'Ireland',
    'english' => 'United Kingdom',
    'English' => 'United Kingdom',
    'Estonia' => 'Estonia',
    'Estonian' => 'Estonia',
    'Finnish' => 'Finland',
    'Francaise' => 'France',
    'French' => 'France',
    'german' => 'Germany',
    'Geman' => 'Germany',
    'German' => 'Germany',
    'German .' => 'Germany',
    'Georgian' => 'Georgia',
    'Georgisch' => 'Georgia',
    'Greek' => 'Greece',
    'Hungary' => 'Hungary',
    'Hungarian' => 'Hungary',
    'India' => 'India',
    'indian' => 'India',
    'Indian' => 'India',
    'Indien' => 'India',
    'Indonesia' => 'Indonesia',
    'Indonesian' => 'Indonesia',
    'Indonisian' => 'Indonesia',
    'iran' => 'Iran',
    'Iran' => 'Iran',
    'Iranian' => 'Iran',
    'irish' => 'Ireland',
    'Irish' => 'Ireland',
    'Irish. British' => 'Ireland',
    'Israeli' => 'Israel',
    'Israelian' => 'Israel',
    'italian' => 'Italy',
    'Italian' => 'Italy',
    'Italien' => 'Italy',
    'Japan' => 'Japan',
    'Japanese' => 'Japan',
    'Japaneses' => 'Japan',
    'Jemen' => 'Yemen',
    'JPN' => 'Japan',
    'Kasachisch' => 'Kazakhstan',
    'Kenya' => 'Kenya',
    'Korea' => 'South Korea',
    'Korean' => 'South Korea',
    'Kyrgyz' => 'Kyrgyzstan',
    'Kyrgyz Republic' => 'Kyrgyzstan',
    'Latvian' => 'Latvia',
    'Litauen' => 'Lithuania',
    'Lithuanian' => 'Lithuania',
    'Malaysia' => 'Malaysia',
    'malaysian' => 'Malaysia',
    'Malaysian' => 'Malaysia',
    'Marrocan' => 'Morocco',
    'Mauritian' => 'Mauritius',
    'Mexican' => 'Mexico',
    'Moldavian' => 'Moldova',
    'Mongolian' => 'Mongolia',
    'Netherland' => 'Netherlands',
    'Netherlands' => 'Netherlands',
    'New Zealand' => 'New Zealand',
    'Nigeria' => 'Nigeria',
    'Nigerian' => 'Nigeria',
    'Norway' => 'Norway',
    'norwegian' => 'Norway',
    'Norwegian' => 'Norway',
    'Österreich' => 'Austria',
    'Pakistan' => 'Pakistan',
    'Pakistani' => 'Pakistan',
    'Palestinian' => 'Palestine',
    'Persian' => 'Iran',
    'Peruanian' => 'Peru',
    'Peruvian' => 'Peru',
    'Philippines' => 'Philippines',
    'Polen' => 'Poland',
    'polish' => 'Poland',
    'Polish' => 'Poland',
    'Polnisch' => 'Poland',
    'Portugese' => 'Portugal',
    'Portuguese' => 'Portugal',
    'Republic of Congo' => 'Congo, Republic of the',
    'Romania' => 'Romania',
    'Romanian' => 'Romania',
    'Rumanian' => 'Romania',
    'Rumänisch' => 'Romania',
    'russian federation' => 'Russia',
    'Russian' => 'Russia',
    'russisch' => 'Russia',
    'Russisch' => 'Russia',
    'Saudi Arabian' => 'Saudi Arabia',
    'Schwedisch' => 'Sweden',
    'Scotland' => 'United Kingdom',
    'Scottish' => 'United Kingdom',
    'Serbian' => 'Serbia',
    'Singapore' => 'Singapore',
    'Singaporean' => 'Singapore',
    'Singapur' => 'Singapore',
    'Slovac' => 'Slovakia',
    'Slovakian' => 'Slovakia',
    'Somalian' => 'Somalia',
    'South African' => 'South Africa',
    'Spanish' => 'Spain',
    'Spanissh' => 'Spain',
    'Sri Lanka' => 'Sri Lanka',
    'Swedish' => 'Sweden',
    'Swiss' => 'Switzerland',
    'Syria' => 'Syria',
    'Syrian' => 'Syria',
    'Syrien' => 'Syria',
    'Taiwanese' => 'Taiwan',
    'Tanzanian' => 'Tanzania',
    'Trinidadian' => 'Trinidad',
    'Turkiye' => 'Turkey',
    'Turkish' => 'Turkey',
    'Türkish' => 'Turkey',
    'Türkisch' => 'Turkey',
    'Ukraine' => 'Ukraine',
    'Ucrainian' => 'Ukraine',
    'UK' => 'United Kingdom',
    'Ukrainian' => 'Ukraine',
    'usa' => 'United States of America',
    'USA' => 'United States of America',
    'US-American' => 'United States of America',
    'US' => 'United States of America',
    'US American' => 'United States of America',
    'Usbekin' => 'Uzbekistan',
    'Usbekistan' => 'Uzbekistan',
    'Uzbek' => 'Uzbekistan',
    'U. S.' => 'United States of America',
    'Venezuela' => 'Venezuela',
    'Vietnam' => 'Vietnam',
    'Vietnamese' => 'Vietnam',
    'Vietnamesisch' => 'Vietnam',
);

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

my @header_row = qw(cardnumber surname firstname title othernames initials streetnumber streettype address address2 city state zipcode country email phone mobile fax emailpro phonepro B_streetnumber B_streettype B_address B_address2 B_city B_state B_zipcode B_country B_email B_phone dateofbirth branchcode categorycode dateenrolled dateexpiry gonenoaddress lost debarred debarredcomment contactname contactfirstname contacttitle guarantorid borrowernotes relationship sex password flags userid opacnote contactnote sort1 sort2 altcontactfirstname altcontactsurname altcontactaddress1 altcontactaddress2 altcontactaddress3 altcontactstate altcontactzipcode altcontactcountry altcontactphone smsalertnumber privacy patron_attributes);
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

    my $patron_category = "NORMAL";
    my $alice_category = $row->{"User Loan Category"};
    if ($alice_category eq "reduced") {
        $patron_category = "REDUCED";
    } elsif ($alice_category eq "Volunteer (normal)") {
        $patron_category = "VOLUNTEER";
    } elsif ($alice_category eq "Volunteer (reduced)") {
        $patron_category = "RVOLUNTEER";
    } elsif ($alice_category eq "VHS Teacher or Hon.") {
        $patron_category = "VHS";
    }

    my $debarred = "";
    if ($alice_category =~ "Banned") {
        $debarred = "9999-12-31";
    }

    my $date_enrolled = $row->{"Membership Start Date"};
    $date_enrolled =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/g;
    my $date_expiry = $row->{"Membership expiry date"};
    $date_expiry =~ s/(\d\d)\/(\d\d)\/(\d\d\d\d)/$3-$2-$1/g;

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

    my $country = "";
    my $country2 = "";
    if ((length $row->{"User defined field 1"}) > 1) {
        $country = $row->{"User defined field 1"};
    } elsif ((length $row->{"User defined field 5"}) > 1) {
        $country = $row->{"User defined field 5"};
    }

    if ($country =~ /(.*)[\/\-,](.*)/) {
        $country = $1;
        $country2 = $2;
    }

    # Trim whitespace
    $country =~ s/^\s+|\s+$//g;
    $country2 =~ s/^\s+|\s+$//g;

    if (!$countries{$country}) {
        if ($country ne "") {
            #print "Missing country: '$country'\n";
            $country = "";
        }
    } else {
        $country = $countries{$country};
    }

    if ($country2 ne "") {
        if (!$countries{$country2}) {
            #print "Missing country: '$country2'\n";
            $country2 = "";
        } else {
            $country2 = $countries{$country2};
        }
    }
    
    my $patron_attributes = "";
    if ($country ne "") {
        $patron_attributes = "\"COUNTRY:$country\"";
    }

    if ($country2 ne "") {
        $patron_attributes .= ",\"COUNTRY:$country2\"";
    }

    # Generate a sort-of random password
    my $pass_dict = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    my $pass_dict_len = length $pass_dict;
    my $password = "";
    for (my $i = 0; $i < 24; $i++) {
        $password .= substr($pass_dict, int(rand($pass_dict_len)), 1);
    }

    # Combine all comment fields into one string, if they exist
    my $comment_start_col = 3;
    my $user_def_3_len = length $row->{"User defined field 3"};
    my $user_def_4_len = length $row->{"User defined field 4"};
    if ($user_def_3_len < 10 || $user_def_4_len == 4) {
        # For some borrowers, previous columns get pushed into the user
        # defined fields in the export. If that's the case with this user,
        # exclude those columns from the borrower note.
        $comment_start_col = 11;
    }

    my $notes = "";

    if ($row->{Comment}) {
        $notes .= $row->{Comment};
        # Trim whitespace
        $notes =~ s/^\s+|\s+$//g;
        if (!($notes =~ /[\.\!]$/)) {
            $notes .= ".";
        }
        $notes .= " ";
    }

    if ($row->{Message}) {
        $notes .= $row->{Message};
        # Trim whitespace
        $notes =~ s/^\s+|\s+$//g;
        if (!($notes =~ /[\.\!]$/)) {
            $notes .= ".";
        }
        $notes .= " ";
    }

    for (my $i = $comment_start_col; $i < 21; $i++) {
        my $col_name = "User defined field $i";
        if ($row->{$col_name} && length $row->{$col_name} > 1) {
            $notes .= $row->{$col_name} . " ";
        }
    }

    # Trim whitespace
    $notes =~ s/^\s+|\s+$//g;

    # A couple of patrons have 1-character notes for some reason. Clean them
    # up.
    if (length $notes < 2) {
        $notes = "";
    }

    my $barcode = add_check_digit($row->{Barcode});

    my @out_row = [
        $barcode, # cardnumber
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
        $notes, # borrowernotes
        "", # relationship
        $row->{Sex}, # sex
        $password, # password
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
        $patron_attributes, # patron_attributes
    ];
    $out_csv->print($out_fh, @out_row);
    $member_count += 1;
}
$in_csv->eof or $in_csv->error_diag();

close($in_fh) or die "$output_path: $!";
close($out_fh) or die "$output_path: $!";

print("Member count: $member_count\n");

