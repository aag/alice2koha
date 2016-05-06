#!/usr/bin/perl

# This script takes a "USMARC export with copy information" data export from
# Alice and converts it to a MARC file that can be imported into Koha.
#
# One preprocessing step on the input file is needed before running this script:
# 1. Convert the exported .dat file from UTF-16 to UTF-8.
#
# Make sure to configure the BRANCH and %types values below.
# - This script (and Alice itself?) only supports items that are located in a
#   single branch, which is specified in the BRANCH constant. This branch has
#   to be first configured as a library in Koha under "Administration" ->
#   "Libraries and Groups".
# - You must specify a mapping from Alice types to Koha types in the
#   %types hash. These types have to be first configured in Koha under
#   "Administration" -> "Item types".
# - You must specify a mapping from Alice collection codes to Koha collection
#   codes in the %ccodes hash. These codes have to be first configured in
#   Koha under "Administration" -> "Authorized values" -> "CCODE". If you
#   have entered the exact same values in Koha as you had in Alice, you can
#   leave this hash empty.

# TODO:
# - Set the 952$7 "Not for loan" value based on collection (Reference?)

use strict;
use warnings;

use MARC::Batch;

use constant BRANCH => "IELD";
my %types = (
    '[Audio Cassette]' => 'CASSETTE',
    '[Compact Disc]' => 'CD',
    '[DVD]' => 'DVD',
    '[Flash card]' => 'FLASHCARD',
    '[Game]' => 'GAME',
    '[Other]' => 'OTHER',
    '[Picture]' => 'PICTURE',
    '[Sound Recording]' => 'CD',
    '[Text]' => 'TEXT',
    '[Video recording]' => 'DVD',
);

my %ccodes = (
    '0 - General works' => 'General Works',
    '1 - Philosophy' => 'Philosophy',
    '2 - Religion' => 'Religion',
    '3 - Social Sciences' => 'Social Sciences',
    '4 - Language' => 'Language',
    '5 - Pure Sciences' => 'Pure Sciences',
    '6 - Applied Sciences' => 'Applied Sciences',
    '7 - Arts&Recreations' => 'Arts Recreation',
    '8 - Literature' => 'Literature',
    '9 - History' => 'History',
    'Biography' => 'Biography',
    'Biography Collection' => 'Biography',
    'Course Book' => 'Course Book',
    'Detective Stories' => 'Detective Stories',
    'Easy Readers' => 'Easy Readers',
    'Fiction' => 'Fiction',
    'Graphic Books' => 'Graphic Books',
    'Juvenile Fiction' => 'Juvenile Fiction',
    'Juvenile Non-Fiction' => 'Juvenile Non-Fiction',
    'Reference' => 'Reference',
    'Science Fiction' => 'Science Fiction',
    'Short Stories' => 'Short Stories',
    'Short-Story Coll.' => 'Short Stories',
    'TESL' => 'TESL',
    'Travel' => 'Travel',
);

# ======================================
# = No customization needed below here =
# ======================================

my $num_args = @ARGV;
if ($num_args != 2) {
    print "Usage: convert_marc.pl <INPUT> <OUTPUT>\n";
    exit;
}

my $input_path = $ARGV[0];
my $output_path = $ARGV[1];

my $batch = MARC::Batch->new('USMARC', $input_path);

open(OUTPUT, "> $output_path") or die $!;
while (my $record = $batch->next()) {
    my $koha_holdings_field = MARC::Field->new(
        952, '', '',
        'a' => BRANCH, # Home branch AKA owning library
        'b' => BRANCH, # Holding branch
    );

    my $barcode;
    my $item_type;
    my $collection_code;

    # Item type (e.g. Text, DVD, CD)
    if ($record->field('245') && $record->field('245')->subfield('h')) {
        my $alice_type = $record->field('245')->subfield('h');
        $item_type = $types{$alice_type};
    }

    # 852 is a repeating field
    my @fields_852 = $record->field('852');
    foreach my $field_852 (@fields_852) {
        # Barcode
        if ($field_852->subfield('p')) {
            $barcode = $field_852->subfield('p');
        }

        # Collection code (e.g. Fiction, Biography)
        if ($field_852->subfield('k')) {
            my $alice_collection_code = $field_852->subfield('k');
            if (!$ccodes{$alice_collection_code}) {
                print $alice_collection_code . "\n";
                $collection_code = $alice_collection_code;
            } else {
                $collection_code = $ccodes{$alice_collection_code};
            }
        }
    }

    if ($barcode) {
        $koha_holdings_field->add_subfields('p', $barcode);
    }

    if ($collection_code) {
        $koha_holdings_field->add_subfields('8', $collection_code);
    }

    if ($item_type) {
        $koha_holdings_field->add_subfields('y', $item_type);
    }

    $record->append_fields($koha_holdings_field);

    print OUTPUT $record->as_usmarc();
}

close(OUTPUT);

