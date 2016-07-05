#!/usr/bin/perl

# This script takes a "USMARC export with copy information" data export
# in the "Text file - Unicode (.txt)" format from Alice and downloads the
# cover image for that ISBN from LibraryThing to the hard drive. The images
# are named ISBN.jpg.
#
# Two preprocessing steps on the input file is needed before running this
# script:
# 1. Convert the exported .dat file from UTF-16 to UTF-8.
#    $ iconv -f UTF-16LE -t UTF-8 -o alice_export.mrc MARCXB01.dat
#
# 2. Open the file in MarcEdit and remove the first entry, which just contains
#    the name of the library.
#
# After downloading the covers, you also need to create an idlink.txt file
# to map the biblionumbers to image files:
# 1. Dump the biblionumbers and ISBNs from the Koha database by running this
#    MySQL query:
#    SELECT biblionumber, isbn
#    FROM biblioitems
#    WHERE isbn IS NOT NULL
#    INTO OUTFILE '/tmp/isbn_biblio.txt'
#    FIELDS TERMINATED BY ','
#    LINES TERMINATED BY '\n';
#
# 2. Transfer the file /tmp/isbn_biblio.txt to the computer with the alice2koha
#    repo on it.
# 3. Add the image file extensions with this command:
#    $ sed 's/$/.jpg/' biblio_isbn.txt > idlink.txt
# 4. Add all the images and the idlink.txt file to a zip file.
# 5. Make sure the Apache and PHP max file upload sizes are set to a value
#    larger than the zip file.
# 6. Upload the zip file to Koha on the "Upload local cover image" page in
#    "Administration" -> "Tools".

use strict;
use warnings;

use Algorithm::CheckDigits;
use File::Fetch;
use MARC::Batch;
use Storable qw(nstore retrieve);

my $num_args = @ARGV;
if ($num_args != 3) {
    print "Usage: download_covers.pl <API_KEY> <INPUT_FILE> <OUTPUT_DIR>\n";
    exit;
}

my $api_key = $ARGV[0];
my $infile_path = $ARGV[1];
my $outdir_path = $ARGV[2];
if (!($outdir_path =~ /\/$/)) {
    $outdir_path .= '/';
}
my $downloaded_covers_path = "downloaded_covers.bin";

my $isbn_checker = CheckDigits('isbn');
my $isbn13_checker = CheckDigits('isbn13');

my $count = 0;
my $download_count = 0;
my %downloaded_covers;
my $errors = 0;

if (-e $downloaded_covers_path && -s $downloaded_covers_path > 0) {
    %downloaded_covers = %{retrieve($downloaded_covers_path)};
    print "Downloaded covers loaded. " . scalar(keys %downloaded_covers) . " covers found.\n";
}

my $batch = MARC::Batch->new('USMARC', $infile_path);
while (my $record = $batch->next()) {
    if (!$record->field('020') || !$record->field('020')->subfield('a')) {
        print "No ISBN found.\n";
        next;
    }
    $count++;

    my $isbn = $record->field('020')->subfield('a');
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
        print " Could not get filesize for file $dl_filepath. Maybe your daily quota has been used.\n";
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
        nstore \%downloaded_covers, $downloaded_covers_path;
        print " ->"
    }
    
    print "\n";

    sleep 1;
}

print "Saving downloaded covers list\n";
nstore \%downloaded_covers, $downloaded_covers_path;

if (!$errors) {
    print "\nDone. All ISBNs have been processed.\n";
}
