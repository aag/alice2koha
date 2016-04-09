#!/usr/bin/perl

# This script takes a text file with 1 ISBN number per line and downloads the
# cover image for that ISBN from LibraryThing to the hard drive. The images
# are named ISBN.jpg.

use strict;
use warnings;

use Algorithm::CheckDigits;
use File::Fetch;
use Storable qw(nstore_fd fd_retrieve);

my $numArgs = @ARGV;
if ($numArgs != 3) {
    print "Usage: download_covers.pl <API_KEY> <INPUT_FILE> <OUTPUT_DIR>\n";
    exit;
}

my $api_key = $ARGV[0];
my $infile_path = $ARGV[1];
my $outdir_path = $ARGV[2];
my $downloaded_covers_path = "downloaded_covers.bin";

open(my $in_fh, $infile_path) or die "Could not open $infile_path: $!";

my $isbn_checker = CheckDigits('isbn');
my $isbn13_checker = CheckDigits('isbn13');

my $count = 0;
my $download_count = 0;
my %downloaded_covers;
my $errors = 0;

if (-e $downloaded_covers_path && -s $downloaded_covers_path > 0) {
    open(my $downloaded_covers_fh, $downloaded_covers_path) or die "Could not open $downloaded_covers_path: $!";

    %downloaded_covers = %{fd_retrieve($downloaded_covers_fh)};
    print "Downloaded covers loaded. " . scalar(keys %downloaded_covers) . " covers found.\n";

    close($downloaded_covers_fh);
}

open(my $downloaded_covers_fh, '>', $downloaded_covers_path) or die "Could not open $downloaded_covers_path: $!";
while (my $isbn = <$in_fh>) { 
    $count++;
    chomp($isbn);
    print $count . ": " . $isbn;

    if (!$isbn_checker->is_valid($isbn) && !$isbn13_checker->is_valid($isbn)) {
        print " Invalid ISBN. Skipping.\n";
        next;
    }

    my $image_path = $outdir_path . $isbn . ".jpg";
    if ($downloaded_covers{$isbn} || -e $image_path) {
        print " Already downloaded. Skipping.\n";

        if (!$downloaded_covers{$isbn} && -e $image_path) {
            $downloaded_covers{$isbn} = 1;
        }

        next;
    }
    
    my $uri = "http://www.librarything.com/devkey/" . $api_key . "/large/isbn/" . $isbn;
    my $ff = File::Fetch->new(uri => $uri);

    my $where = $ff->fetch(to => $outdir_path);
    my $dl_filepath = $outdir_path . $ff->output_file;

    if ($ff->error()) {
        print " ERROR: " . $ff->error() . "\n";
        unlink $dl_filepath;
       
        if ($ff->error() =~ /was not created/) {
            print " File was not created. Maybe your daily quota has been used.\n";
            $errors = 1;
            last;
        }

        # Don't store in %downloaded_covers. We'll try again later.
        next;
    }

    my $filesize = -s $dl_filepath;
    if (!(defined $filesize)) {
        print " Could not get filesize. Maybe your daily quota has been used.\n";
        $errors = 1;
        last;
    }
    
    print " size: " . $filesize;

    if ($filesize == 43) {
        print " Empty cover, deleting.";
        unlink $dl_filepath;
    } else {
        rename $dl_filepath, $image_path;
    }

    $download_count++;
    $downloaded_covers{$isbn} = 1;
    if (!($download_count % 10)) {
        seek $downloaded_covers_fh,0,0;
        nstore_fd \%downloaded_covers, $downloaded_covers_fh;
        print " ->"
    }
    
    print "\n";

    sleep 1;
}

print "Saving downloaded covers list\n";
seek $downloaded_covers_fh,0,0;
nstore_fd \%downloaded_covers, $downloaded_covers_fh;

close($in_fh);
close($downloaded_covers_fh);

if (!$errors) {
    print "\nDone. All ISBNs have been processed.\n";
}


