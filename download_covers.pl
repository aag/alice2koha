#!/usr/bin/perl

# This script takes a text file with 1 ISBN number per line and downloads the
# cover image for that ISBN from LibraryThing to the hard drive. The images
# are named ISBN.jpg.

use strict;
use warnings;

use File::Fetch;
use Algorithm::CheckDigits;

my $numArgs = @ARGV;
if ($numArgs != 3) {
    print "Usage: download_covers.pl <API_KEY> <INPUT_FILE> <OUTPUT_DIR>\n";
    exit;
}

my $api_key = $ARGV[0];
my $infile_path = $ARGV[1];
my $outdir_path = $ARGV[2];

open my $fh, $infile_path or die "Could not open $infile_path: $!";

my $isbn_checker = CheckDigits('isbn');
my $isbn13_checker = CheckDigits('isbn13');

my $count = 0;
while (my $isbn = <$fh>) { 
    $count++;
    chomp($isbn);
    print $count . ": " . $isbn;

    my $outfile_path = $outdir_path . $isbn . ".jpg";
    if (-e $outfile_path) {
        print " Already downloaded. Skipping.\n";
        next;
    }


    if (!$isbn_checker->is_valid($isbn) && !$isbn13_checker->is_valid($isbn)) {
        print " Invalid ISBN. Skipping.\n";
        next;
    }
    
    my $uri = "http://www.librarything.com/devkey/" . $api_key . "/large/isbn/" . $isbn;
    my $ff = File::Fetch->new(uri => $uri);

    my $where = $ff->fetch( to => $outdir_path );
    my $old_filepath = $outdir_path . $ff->output_file;
    rename $old_filepath, $outfile_path;
    
    print "\n";
    
    sleep 1;
}

close $fh;
