#!/usr/bin/perl

# This script takes a "USMARC export with copy information" data export from
# Alice and prints information about all items that have an invalid ISBN. The
# script only verifies the format of the ISBNs, not whether or not they match
# the item.
#
# One preprocessing step on the input file is needed before running this script:
# 1. Convert the exported .dat file from UTF-16 to UTF-8.

use strict;
use warnings;

use Algorithm::CheckDigits;
use MARC::Batch;
use Scalar::Util qw(looks_like_number);

# The categories that have items with EANs and not ISBNs
my %ean_categories = (
    '[DVD]' => 1,
    '[Compact Disc]' => 1,
);

# The location abbreviations that are used in the call numbers
my %location_abbreviations = (
    '0 - General works' => '0',
    '1 - Philosophy' => '1',
    '2 - Religion' => '2',
    '3 - Social Sciences' => '3',
    '4 - Language' => '4',
    '5 - Pure Sciences' => '5',
    '6 - Applied Sciences' => '6',
    '7 - Arts&Recreations' => '7',
    '8 - Literature' => '8',
    '9 - History' => '9',
    'Biography' => 'B',
    'Biography Collection' => 'BC',
    'Course Book' => 'CB',
    'Detective Stories' => 'X',
    'Easy Readers' => 'ER',
    'Fiction' => '',
    'Graphic Books' => 'G',
    'Juvenile Fiction' => 'JF',
    'Juvenile Non-Fiction' => 'JF',
    'Reference' => 'R',
    'Science Fiction' => 'SF',
    'Short Stories' => 'SS',
    'Short-Story Coll.' => 'SSC',
    'TESL' => 'TESL',
    'Travel' => 'T',
);

# ======================================
# = No customization needed below here =
# ======================================

my $num_args = @ARGV;
if ($num_args != 1) {
    print "Usage: find_invalid_isbns.pl <INPUT>\n";
    exit;
}

my $input_path = $ARGV[0];

my $isbn_checker = CheckDigits('isbn');
my $isbn13_checker = CheckDigits('isbn13');
my $ean_checker = CheckDigits('ean');

my $batch = MARC::Batch->new('USMARC', $input_path);
my %rows;

while (my $record = $batch->next()) {
    if ($record->field('020') && $record->field('020')->subfield('a')) {
        my $isbn = $record->field('020')->subfield('a');
        chomp($isbn);

        if (!$isbn_checker->is_valid($isbn)
            && !$isbn13_checker->is_valid($isbn)
        ) {

            my $title = 'unknown title';
            if ($record->field('245') && $record->field('245')->subfield('a')) {
                $title = $record->field('245')->subfield('a');
                utf8::decode($title);
            }

            my $author = 'unknown author';
            if ($record->field('100') && $record->field('100')->subfield('a')) {
                $author = $record->field('100')->subfield('a');
                utf8::decode($author);
            }

            my $barcode;
            my @fields_852 = $record->field('852');
            foreach my $field_852 (@fields_852) {
                # Barcode
                if ($field_852->subfield('p')) {
                    $barcode = $field_852->subfield('p');
                }
            }

            my $alice_type = 'unknown type';
            if ($record->field('245') && $record->field('245')->subfield('h')) {
                $alice_type = $record->field('245')->subfield('h');

                # If the category contains items with EAN identifiers, then
                # also allow valid EANs
                if (exists $ean_categories{$alice_type}) {
                    if ($ean_checker->is_valid($isbn)) {
                        next;
                    } else {
                        $title .= " " . $alice_type;
                    }
                }
            }

            my $loc_abbr = '';
            my $location = 'unknown location';
            if ($record->field('852') && $record->field('852')->subfield('k')) {
                $location = $record->field('852')->subfield('k');
                $loc_abbr = $location_abbreviations{$location};
            }

            my $classification_num = '';
            my $item_num = '';
            if ($record->field('082')) {
                if ($record->field('082')->subfield('a')) {
                    $classification_num = $record->field('082')->subfield('a');
                }

                if ($record->field('082')->subfield('b')) {
                    $item_num = $record->field('082')->subfield('b');
                }
            }

            my $call_number = $loc_abbr;
            
            # Rules for how the location is displayed the in call number
            if ($loc_abbr ne '' && !looks_like_number($loc_abbr)) {
                $call_number .= ' ';
            }

            if ($classification_num ne '') {
                $classification_num .= ' ';
            }

            $call_number .= "$classification_num$item_num";

            my $html_row = <<"END_ROW";
                <tr>
                    <td class="checkholder"><input type="checkbox"></td>
                    <td class="checkholder"><input type="checkbox"></td>
                    <td class="identifier">$call_number</td>
                    <td class="identifier">$barcode</td>
                    <td>$title</td>
                    <td>$author</td>
                    <td class="identifier">$isbn</td>
                </tr>
END_ROW

            my $row_key = $call_number . $barcode;
            if ($location eq "Fiction") {
                $row_key = 'F' . $row_key;
            }

            $rows{$row_key} = $html_row;

            next;
        }
    }
}

my $html_header = <<'END_HEADER';
<html>
<head>
<link href="https://cdnjs.cloudflare.com/ajax/libs/normalize/4.1.1/normalize.min.css" media="all" rel="stylesheet" type="text/css" >
<style>
    thead th {
        font-size: 14px;
    }

    tbody td {
        border-bottom: 1px solid #ddd;
        border-left: 1px solid #ddd;
        font-size: 12px;
        padding-left: 4px;
        padding-right: 4px;
    }

    .checkholder {
        text-align: center;
    }

    .identifier {
        white-space: nowrap;
    }
</style>
</head>
<body>
    <table>
        <thead>
            <tr>
                <th>Found</th>
                <th>Fixed</th>
                <th>Call Number</th>
                <th>Barcode</th>
                <th>Title</th>
                <th>Author</th>
                <th>ISBN/EAN</th>
            </tr>
        </thead>
        <tbody>
END_HEADER

my $html_footer = <<'END_FOOTER';
        </tbody>
    </table>
</body>
</html>
END_FOOTER


print $html_header;

foreach my $row (sort keys %rows) {
    print $rows{$row};
}

print $html_footer;

