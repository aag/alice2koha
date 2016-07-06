#!/usr/bin/perl

# This script takes a "USMARC export with copy information" data export
# in the "Text file - Unicode (.txt)" format from
# Alice and converts it to a MARC file that can be imported into Koha.
#
# Two preprocessing steps on the input file is needed before running this
# script:
# 1. Convert the exported .dat file from UTF-16 to UTF-8.
#    $ iconv -f UTF-16LE -t UTF-8 -o alice_export.mrc MARCXB01.dat
#
# 2. Open the file in MarcEdit and remove the first entry, which just contains
#    the name of the library.
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

# ddc is Dewey Decimal Classification
use constant CLASSIFICATION => "ddc";

my %types = (
    '[Audio Cassette]' => 'CASSETTE',
    '[Compact Disc]' => 'CD',
    '[DVD]' => 'DVD',
    '[Flash card]' => 'FLASHCARD',
    '[Game]' => 'GAME',
    '[Other]' => 'OTHER',
    '[Picture]' => 'PICTURE',
    '[Sound Recording]' => 'SOUND',
    '[Text]' => 'TEXT',
    '[Video recording]' => 'VIDEO',
);

my %material_types = (
    'CASSETTE' => 'i',
    'CD' => 'i',
    'DVD' => 'g',
    'FLASHCARD' => 'a',
    'GAME' => 'r',
    'OTHER' => 'p',
    'PICTURE' => 'k',
    'SOUND' => 'i',
    'TEXT' => 'a',
    'VIDEO' => 'g',
);

my %ccodes = (
    '0 - General works' => '0 - General Works',
    '1 - Philosophy' => '1 - Philosophy',
    '2 - Religion' => '2 - Religion',
    '3 - Social Sciences' => '3 - Social Sciences',
    '4 - Language' => '4 - Language',
    '5 - Pure Sciences' => '5 - Pure Sciences',
    '6 - Applied Sciences' => '6 - Applied Sciences',
    '7 - Arts&Recreations' => '7 - Arts & Recreations',
    '8 - Literature' => '8 - Literature',
    '9 - History' => '9 - History',
    'Biography' => 'Biography',
    'Biography Collection' => 'Biography Collection',
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
    'Short-Story Coll.' => 'Short-Story Collection',
    'TESL' => 'TESL',
    'Travel' => 'Travel',
);

# ======================================
# = No customization needed below here =
# ======================================

my %check_digits = (
    0 => 'J',
    1 => 'K',
    2 => 'L',
    3 => 'M',
    4 => 'N',
    5 => 'P',
    6 => 'F',
    7 => 'W',
    8 => 'X',
    9 => 'Y',
    10 => 'A',
);

# This subroutine takes an Alice barcode without the interstitial check digit
# and returns it with the check digit inserted.
sub add_check_digit {
    my $barcode = shift;

    if ($barcode =~ /^(B|R)(\d\d\d\d\d)(\d\d\d\d)/) {
        my $type_char = $1;
        my $unique_num = $2;
        my $library_code = $3;
        
        my $sum = 0;
        for (my $i = 0; $i < 5; $i++) {
            $sum += substr($unique_num, $i, 1);
        }

        my $remainder = $sum % 11;
        my $check_digit = $check_digits{$remainder};

        return "$type_char$unique_num$check_digit$library_code";
    }

    return "";
}

my $num_args = @ARGV;
if ($num_args != 2) {
    print "Usage: convert_marc.pl <INPUT> <OUTPUT>\n";
    exit;
}

my $input_path = $ARGV[0];
my $output_path = $ARGV[1];

my $batch = MARC::Batch->new('USMARC', $input_path);

open(my $out_fh, "> $output_path") or die $!;
while (my $record = $batch->next()) {
    my $koha_holdings_field = MARC::Field->new(
        952, '', '',
        'a' => BRANCH, # Home branch AKA owning library
        'b' => BRANCH, # Holding branch
    );

    my $koha_entries_field = MARC::Field->new(
        942, '', '',
        '2' => CLASSIFICATION, # Source of classification or shelving scheme
    );

    my $barcode;
    my $item_type;
    my $collection_code;

    # Item type (e.g. Text, DVD, CD)
    if ($record->field('245') && $record->field('245')->subfield('h')) {
        my $alice_type = $record->field('245')->subfield('h');
        $item_type = $types{$alice_type};
    }

    # Cataloging source
    if ($record->field('040')) {
        # Add transcribing agency
        $record->field('040')->add_subfields('c', BRANCH);
    }

    # 852 is a repeating field
    my @fields_852 = $record->field('852');
    foreach my $field_852 (@fields_852) {
        # Barcode
        if ($field_852->subfield('p')) {
            $barcode = $field_852->subfield('p');
            $barcode = add_check_digit($barcode);
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
        $koha_entries_field->add_subfields('c', $item_type);
        $koha_holdings_field->add_subfields('y', $item_type);

        # Set material type in the leader
        my $material_type = $material_types{$item_type};
        my $leader_substring = 'n' . $material_type . 'm';
        my $leader = $record->leader();
        $leader =~ s/nam/$leader_substring/g;
        $record->leader($leader);
    }

    $record->append_fields($koha_entries_field);
    $record->append_fields($koha_holdings_field);

    print $out_fh $record->as_usmarc();
}

close($out_fh);

