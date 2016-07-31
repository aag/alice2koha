#!/usr/bin/perl

# This script takes an "Publisher" data export ("Management" ->
# "Authority Lists" -> "Publisher") in the "Text file - Unicode (.txt)" format
# from Alice and converts it to an Authority MARC file that can be
# imported into Koha.
#
# A preprocessing step on the input file is needed before running this
# script:
# 1. Convert the exported .txt file from UTF-16 to UTF-8.
#    $ iconv -f UTF-16LE -t UTF-8 -o publishers.txt PUBLIL00.txt
#
use strict;
use warnings;

use MARC::Record;

my $num_args = @ARGV;
if ($num_args != 2) {
    print "Usage: convert_publishers.pl <INPUT> <OUTPUT>\n";
    exit;
}

my $input_path = $ARGV[0];
my $output_path = $ARGV[1];

open(my $in_fh, $input_path) or die "Could not open $input_path: $!";
open(my $out_fh, "> $output_path") or die $!;

my $authority_count = 0;
while (my $line = <$in_fh>) {
    chomp $line;

    if ($line =~ /^\w{6}  (\w.*?)             \s+(\w.*?)\s+(\d\d)\/(\d\d)\/(\d\d\d\d)/) {
        $authority_count++;

        my $name = $1;
        my $location = $2;
        my $day = $3;
        my $month = $4;
        my $year = $5;
        my $name_length = (length "$authority_count") + (length $name) + 1;
        my $year_short = substr $year, 2, 2;

        my $marc_record = MARC::Record->new();
        $marc_record->leader("002${name_length}nz  a2200109n  4500");

        my $control_num_field = MARC::Field->new('001', $authority_count);
        my $control_num_id_field = MARC::Field->new('003', 'OSt');
        my $last_transaction_field = MARC::Field->new(
            '005',
            "$year$month${day}120000.0"
        );

        my $control_008_field = MARC::Field->new(
            '008',
            "$year_short$month${day}||\\aca||aabn\\\\\\\\\\\\\\\\\\\\\\|\\a|a\\\\\\\\\\d"
        );

        my $cat_source_field = MARC::Field->new(
            '040', '', '',
            'a' => "OSt", # Cataloging Source
        );

        my $corporate_name_field = MARC::Field->new(
            '110', '2', '',
            'a' => $name, # Personal name
        );

        my $type_field = MARC::Field->new(
            '942', '', '',
            'a' => "CORPO_NAME",
        );

        $marc_record->append_fields($control_num_field);
        $marc_record->append_fields($control_num_id_field);
        $marc_record->append_fields($last_transaction_field);
        $marc_record->append_fields($control_008_field);
        $marc_record->append_fields($cat_source_field);
        $marc_record->append_fields($corporate_name_field);
        $marc_record->append_fields($type_field);

        print $out_fh $marc_record->as_usmarc();
    }
}

close($in_fh);
close($out_fh);

print "$authority_count publishers found.\n";
