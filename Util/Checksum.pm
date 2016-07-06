package Util::Checksum;
use strict;
use warnings;

use Exporter qw(import);
 
our @EXPORT_OK = qw(add_check_digit);

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
# The check digit algorithm is described here:
# https://www.dlsoft.com/support/kbase/u1alice.txt
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


