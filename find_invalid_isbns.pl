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

my $numArgs = @ARGV;
if ($numArgs != 1) {
    print "Usage: find_invalid_isbns.pl <INPUT>\n";
    exit;
}

my $inputPath = $ARGV[0];

my $isbn_checker = CheckDigits('isbn');
my $isbn13_checker = CheckDigits('isbn13');
my $ean_checker = CheckDigits('ean');

my $batch = MARC::Batch->new('USMARC', $inputPath);

while (my $record = $batch->next()) {
    if ($record->field('020') && $record->field('020')->subfield('a')) {
        my $isbn = $record->field('020')->subfield('a');
        chomp($isbn);

        if (!$isbn_checker->is_valid($isbn)
            && !$isbn13_checker->is_valid($isbn)
        ) {

            my $aliceType = "unknown";
            if ($record->field('245') && $record->field('245')->subfield('h')) {
                $aliceType = $record->field('245')->subfield('h');
                if ($aliceType eq "[DVD]" || $aliceType eq "[Compact Disc]") {
                    next;
                }
            }

            my $title = "unknown";

            if ($record->field('245') && $record->field('245')->subfield('a')) {
                $title = $record->field('245')->subfield('a');
            }

            print "$isbn, $title, $aliceType\n";
            next;
        }
    }
}

