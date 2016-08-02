#!/usr/bin/perl

# This script takes a "USMARC export with copy information" data export
# in the "Text file - Unicode (.txt)" format from
# Alice and converts it to a MARC file that can be imported into Koha.
#
# Two preprocessing steps on the input file is needed before running this
# script:
# 1. Convert the exported .dat file from UTF-16 to UTF-8.
#    $ iconv -f UTF-16LE -t UTF-8 -o alice_export.mrc MARCXB00.dat
#
# 2. Open the file in MarcEdit and remove the first entry, which just contains
#    the name of the library.
#
# The IELD stored accession numbers in the "topics" field of each item. To
# import this data as well, you will first need to export the topics from Alice.
# You can do this by going to "Alice 6.00" -> "Management" -> "Catalogs" ->
# "Topic" and choosing "03 Detailed - no notes" from the dropdown. Then you will
# need to convert the exported file to UTF-8 and convert the line endings.
# $ uconv --remove-signature -f UTF-16LE -t UTF-8 -o topics.txt TOPICC00.txt
# $ dos2unix topics.txt
#
# Once converted, place the topics.txt file in the same directory as this
# script.
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

use Cwd 'abs_path';
use MARC::Batch;

use lib '.';

use Util::Barcode qw(add_check_digit);

use constant BRANCH => "IELD";

# ddc is Dewey Decimal Classification
use constant CLASSIFICATION => "ddc";

my %types = (
    '[Audio Cassette]' => 'CASSETTE',
    '[Compact Disc]' => 'AUDIOBOOK',
    '[DVD]' => 'DVD',
    '[Flash card]' => 'FLASHCARD',
    '[Game]' => 'GAME',
    '[Other]' => 'OTHER',
    '[Picture]' => 'PICTURE',
    '[Sound Recording]' => 'SOUND',
    '[Text]' => 'BOOK',
    '[Video recording]' => 'VIDEO',
);

my %material_types = (
    'CASSETTE' => 'i',
    'AUDIOBOOK' => 'i',
    'DVD' => 'g',
    'FLASHCARD' => 'a',
    'GAME' => 'r',
    'OTHER' => 'p',
    'PICTURE' => 'k',
    'SOUND' => 'i',
    'BOOK' => 'a',
    'VIDEO' => 'g',
);

my %ccodes = (
    '0 - General works' => 'General Works',
    '1 - Philosophy' => 'Philosophy',
    '2 - Religion' => 'Religion',
    '3 - Social Sciences' => 'Social Sciences',
    '4 - Language' => 'Language',
    '5 - Pure Sciences' => 'Pure Sciences',
    '6 - Applied Sciences' => 'Applied Sciences',
    '7 - Arts&Recreations' => 'Arts & Recreations',
    '8 - Literature' => 'Literature',
    '9 - History' => 'History',
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

my %ccodes_nonfic_numbers = (
    'General works' => '0',
    'Philosophy' => '1',
    'Religion' => '2',
    'Social Sciences' => '3',
    'Language' => '4',
    'Pure Sciences' => '5',
    'Applied Sciences' => '6',
    'Arts & Recreations' => '7',
    'Literature' => '8',
    'History' => '9',
);

my %ccodes_abbrev = (
    'Biography' => 'B ',
    'Biography Collection' => 'BC ',
    'Detective Stories' => 'X ',
    'Easy Readers' => 'ER ',
    'Graphic Books' => 'G ',
    'Juvenile Fiction' => 'JF ',
    'Juvenile Non-Fiction' => 'J',
    'Reference' => 'R ',
    'Science Fiction' => 'SF ',
    'Short Stories' => 'SS ',
    'Short-Story Coll.' => 'SSC ',
    'TESL' => 'TESL ',
    'Travel' => 'T',
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

sub get_topics {
    my ($script_path) = abs_path($0) =~ m/(.*)convert_marc.pl/i;
    my $topics_path = $script_path . 'topics.txt';

    my %topics;
    if (-e $topics_path) {
        print("Loading accession numbers from topics.txt\n");
        open(my $in_fh, $topics_path) or die "Could not open $topics_path: $!";

        # In the file, there is an accession number by itself on one line and
        # the book with that accession number on the next line.
        my $acc_num;
        while (my $line = <$in_fh>) {
            chomp $line;

            if ($line =~ /         (R\d+)      / && defined $acc_num) {
                my $barcode = add_check_digit($1);
                $topics{$barcode} = $acc_num;
                #print("Barcode found: $barcode: $acc_num\n");
            } elsif (index($line, "        ") == -1 && $line =~ /^[\d\w]+/) {
                # If there is no large group of spaces in the line and it
                # contains at least one character, it must be an accession number.
                $acc_num = $line;
                #print "Accession number found: $acc_num\n";
            }
        }
    } else {
        print("Topics file not found. Accession numbers will not be imported.\n");
    }

    return %topics;
}

my $batch = MARC::Batch->new('USMARC', $input_path);

my %topics = get_topics();
my %records;
my @records_no_isbn;
my $num_duplicate_copies = 0;
my $num_input_records = 0;
my $num_books_no_isbn = 0;

# Disable output buffering for STDOUT
{
    my $stdofh = select STDOUT;
    $| = 1;
    select $stdofh;
}

print "Parsing input file...";

while (my $record = $batch->next()) {
    my $is_duplicate_copy = 0;
    $num_input_records++;

    my $output_record = $record;
    my $isbn;
    if ($record->field('020') && $record->field('020')->subfield('a')) {
        $isbn = $record->field('020')->subfield('a');
        if (exists $records{$isbn}) {
            $num_duplicate_copies++;
            $is_duplicate_copy = 1;
            $output_record = $records{$isbn};
        } else {
            $records{$isbn} = $record;
        }
    } else {
        # No ISBN
        push @records_no_isbn, $record;
    }

    my $koha_holdings_field = MARC::Field->new(
        952, '', '',
        'a' => BRANCH, # Home branch AKA owning library
        'b' => BRANCH, # Holding branch
        2 => CLASSIFICATION, # Source of classification or shelving scheme
    );

    my $koha_entries_field = MARC::Field->new(
        942, '', '',
        '2' => CLASSIFICATION, # Source of classification or shelving scheme
    );

    my $barcode;
    my $item_type;
    my $collection_code;
    my $call_number;

    # Item type (e.g. Text, DVD, CD)
    if ($record->field('245') && $record->field('245')->subfield('h')) {
        my $alice_type = $record->field('245')->subfield('h');
        $item_type = $types{$alice_type};
        $record->field('245')->delete_subfield(code => 'h');
    }

    # Cataloging source
    if ($record->field('040') && !$is_duplicate_copy) {
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

            # The barcode only belongs in the item, not the biblio record.
            $field_852->delete_subfield(code => 'p');
        }

        # Collection code (e.g. Fiction, Biography)
        if ($field_852->subfield('k')) {
            my $alice_collection_code = $field_852->subfield('k');
            if (!$ccodes{$alice_collection_code}) {
                #print $alice_collection_code . "\n";
                $collection_code = $alice_collection_code;
            } else {
                $collection_code = $ccodes{$alice_collection_code};
            }
        }
    }

    # 600 is a repeating field
    # Alice writes the subject to the "Personal Name" subject field, but in
    # our collection they are usually "Topical Term" subjects, so move them
    # there.
    my @fields_600 = $record->field('600');
    foreach my $field_600 (@fields_600) {
        if ($field_600->subfield('a')) {
            my $subject_field = MARC::Field->new(
                650, '', '',
                'a' => $field_600->subfield('a'), # Topical term or geographic name entry element
            );

            $record->append_fields($subject_field);
            $record->delete_field($field_600);
        }
    }

    # Add the first number to the Dewey Decimal Classification Number
    my $ddc_num;
    if ($record->field('082') && $record->field('082')->subfield('a') &&
        $collection_code && $ccodes_nonfic_numbers{$collection_code}
    ) {
        my $short_ddc = $record->field('082')->subfield('a');
        my $first_digit = $ccodes_nonfic_numbers{$collection_code};
        $ddc_num = "$first_digit$short_ddc";
    }

    if ($barcode) {
        $koha_holdings_field->add_subfields('p', $barcode);

        if (exists $topics{$barcode}) {
            #print "Barcode $barcode found in topics\n";
            $koha_holdings_field->add_subfields('i', $topics{$barcode});
        } else {
            #print "Barcode $barcode not found in topics\n";
        }
    }

    # DVDs have the collection code of Fiction in Alice, but we want them to
    # be in their own collection.
    if ($collection_code && $collection_code eq "Fiction" && $item_type eq "DVD") {
        $collection_code = "Video";
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

        if ($item_type eq "BOOK" && !$isbn) {
            $num_books_no_isbn++;
        }
    }

    if ($ddc_num) {
        $record->field('082')->update('a', $ddc_num);
    }

    # Call number
    if ($record->field('082')) {
        my $ddc_field = $record->field('082');
        if ($ddc_field->subfield('a') && $ddc_field->subfield('b')) {
            $call_number = $ddc_field->subfield('a') . " " .
                $ddc_field->subfield('b');
        } elsif ($ddc_field->subfield('b')) {
            $call_number = $ddc_field->subfield('b');
        } elsif ($ddc_field->subfield('a')) {
            $call_number = $ddc_field->subfield('a');
        }
    }

    if ($call_number && $collection_code && $ccodes_abbrev{$collection_code}) {
        $call_number = $ccodes_abbrev{$collection_code} . $call_number;
    }

    if ($call_number) {
        $koha_holdings_field->add_subfields('o', $call_number);
    }

    if (!$is_duplicate_copy) {
        $record->append_fields($koha_entries_field);
    }

    $output_record->append_fields($koha_holdings_field);
}

print " done.\n";
print "Writing output file...";

my $output_records = 0;
open(my $out_fh, "> $output_path") or die $!;

# Output the records with no ISBN
foreach my $record (@records_no_isbn) {
    $output_records++;
    print $out_fh $record->as_usmarc();
}

# Output the records with an ISBN
for my $record (values %records) {
    $output_records++;
    print $out_fh $record->as_usmarc();
}

close($out_fh);
print " done.\n\n";

print "Total input records: $num_input_records\n";
print "Total records written: $output_records (plus $num_duplicate_copies duplicate copies)\n";

print "Books without ISBNs: $num_books_no_isbn\n";
