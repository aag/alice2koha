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

# The location abbreviations that are used on the spine stickers
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
            }

            my $alice_type = 'unknown type';
            if ($record->field('245') && $record->field('245')->subfield('h')) {
                $alice_type = $record->field('245')->subfield('h');

                # If the category contains items with EAN identifiers, then
                # also allow valid EANs
                if (exists $ean_categories{$alice_type}
                    && $ean_checker->is_valid($isbn)
                ) {
                    next;
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

            my $sticker = $loc_abbr;
            
            # Rules for how location is printed on spine sticker
            if ($loc_abbr ne '' && !looks_like_number($loc_abbr)) {
                $sticker .= ' ';
            }

            if ($classification_num ne '') {
                $classification_num .= ' ';
            }

            $sticker .= "$classification_num$item_num";

            print "$isbn, $title, $alice_type, $location, sticker: '$sticker'\n";
            next;
        }
    }
}

