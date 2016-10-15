Alice to Koha
=============

This repository contains a collection of Perl scripts that are useful when
migrating from Softlink's Alice ILS to [Koha](https://koha-community.org/).

Note: the scripts in this repository contain many parts that are specific
to the data at the
[International English Library](https://international-library.de), where they
were developed. You will not be able to use them as a drop-in migration
solution. However, it is hoped that this repository will be a useful starting
point for anyone else doing the same migration.

Usage
-----
As mentioned above, you will not be able to follow these steps exactly to
migrate your own data, but this set of steps was used at the library where
these scripts were developed and may be useful as a starting point for your
migration.

1. Install Koha and create an instance using `koha-create`.
2. Visit the web address of the new instance and log in as the DB admin user
  * After initial setup the user information is located in
    /etc/koha/sites/INSTANCE_NAME/koha-conf.xml in the <user> and <pass>
    elements (replace INSTANCE_NAME with the name you entered in step #1)
3. Create a library branch ("Administration" -> "Libraries and Groups").
4. Create your patron categories, but with 0 fees for each category. Otherwise
  all patrons will incur an additional fee on import.
  * We also create an OPERATOR category for IT administrator accounts.
5. Create an “IT Administrator” patron in the OPERATOR category.
  * After creation, go to the patron details page and click the “More”
    dropdown button at the top of the details and choose “Set permissions”.
  * Check superlibrarian and click Save.
  * Log out and log in as the new user.
6. Create the item types for the materials in your library ("Administration"
  -> "Item types").
7. Create Authorised Values for the categories `CCODE`, `DAMAGED`, `LOC`,
  `LOST`, `NOT_LOAN`, and `WITHDRAWN`. See the Koha manual for what these
  categories mean and how to choose values for them.
8. Set up the System Preferences (“Administration” ->
  “Global System Preferences”).
9. Export data from Alice by using the Alice interface. You'll need to create
  these exports:
  * “System” -> “Utilities” -> “Export to MARC” -> “04 USMARC export with copy information”
  * “System” -> “Utilities” -> “Borrower Details Export” -> “01 Tab delimited export of borrower details”
    * Check all boxes under “Who”, “All” under “Select”, “All” under “Contact name”
  * “System” -> “Utilities” -> “Borrower export” -> “01 Tab delimited”
    * Check all boxes under “Who”, “All” in all other  groups
  *"Management" -> "Catalogs" -> "Topic" -> "03 Detailed - no notes"
  * “Circulation” -> “Reports” -> “Fine statistics” -> “01 Fine Statistics”
  * "Management" -> "Authority Lists" -> "Publisher"
  * "Management" -> "Authority Lists" -> "Author”
  * "Management" -> "Authority Lists" -> "Subject”
10. Prepare the exported files by running these commands on a Linux system:
  
  ```
  uconv --remove-signature -f UTF-16LE -t UTF-8 -o checkouts.tsv BOREXB00.dat
  iconv -f UTF-16LE -t UTF-8 -o borrowers.tsv BORRWB00.dat
  iconv -f UTF-16LE -t UTF-8 -o fines.txt FSTATR00.txt
  iconv -f UTF-16LE -t UTF-8 -o alice_export.mrc MARCXB00.dat
  uconv --remove-signature -f UTF-16LE -t UTF-8 -o topics.txt TOPICC00.txt
  dos2unix topics.txt
  iconv -f UTF-16LE -t UTF-8 -o authors.txt AUTHOL00.txt
  iconv -f UTF-16LE -t UTF-8 -o publishers.txt PUBLIL00.txt
  ```
11. Copy all prepared files to the main alice2koha directory.
12. Import patrons
  * Run `./convert_users.pl borrowers.tsv kohausers.csv`
  * Import kohausers.csv into Koha using the web interface under 
    “Tools” -> “Import patrons”.
13. Import items
  * You may have to open alice_export.mrc in
    [MarcEdit](http://marcedit.reeset.net/) and delete the first entry if it
    does not contain any item data. Then save the file.
  * Run `./convert_marc.pl alice_export.mrc koha_import.mrc`
  * Import koha_import.mrc into Koha using the web interface under “Tools”
    -> “Stage MARC records for import”.
  * Click “Manage Staged Records” when the staging is finished.
  * Click “Import this batch into the catalog”.
14. Import fines and checkouts
  * Create the directory `~/alice2koha/` on the web server and upload the
    alice2koha folder to it, along with fines.txt and checkouts.txt.
  * Copy /etc/koha/sites/INSTANCE_NAME/koha-conf.xml on the web server to
    ~/alice2koha/ and chown it to your shell user. (replace INSTANCE_NAME
    with the name you entered in step #1)
  * Run `./import_checkouts.pl checkouts.tsv`
  * Run `./import_fines.pl fines.txt`
15. Import authorities
  * Run `./convert_authors.pl authors.txt authors.mrc`
  * In the Koha web interface under “Tools” -> “Stage MARC records for import”,
    select authors.mrc
  * Set the “Record type” to Authority and click “Stage for import”
  * Click the “Manage staged records” button.
  * Click the “Import this batch into the catalog” button.
  * Run `./convert_subjects.pl subjects.txt subjects.mrc`
  * In the Koha web interface under “Tools” -> “Stage MARC records for import”,
    select subjects.mrc
  * Set the “Record type” to Authority and click “Stage for import”
  * Click the “Manage staged records” button.
  * Click the “Import this batch into the catalog” button.
16. Update the fees on the patron categories to the real ones
  (“Administration” -> “Patron categories”).
17. Define the circulation and fines rules (“Administration” ->
  “Circulation and fines rules”).
18. Set up the calendar in “Tools” -> “Calendar”. You will have to do this
  manually instead of importing it from Alice.
19. Rebuild the Zebra search index by running this command on the web server:
  
  ```
  sudo koha-rebuild-zebra -f --force -u -v INSTANCE_NAME
  ```
  (Replace INSTANCE_NAME with the name you entered in step #1)

You should now have a working Koha installation with all of your media, patrons,
fines and complete checkout history imported from Alice.

Extra Configuration
-------------------
Here are a couple of configuration changes which can be useful:

1. Enable template caching. This gives a small performance boost to each page
  load. You can enable it by editing this file on the web server:
  `/etc/koha/sites/INSTANCE_NAME/koha-conf.xml` (replace INSTANCE_NAME with the
  name you entered during installation.) Go to the end of the file and before
  the line `</config>` insert a new line with this content:
  
  ```
  <template_cache_dir>/tmp</template_cache_dir>
  ```
  This is even more effective if you mount `/tmp` to a tmpfs in-memory disk.
2. Lengthen the number of days kept by the daily backup. By default, Koha only
  keeps 2 days worth of backups. This means if some data gets accidentally
  destroyed or altered, you only have 48 hours to notice it and restore it
  from backup. We prefer to have more time, so we keep the last 2 weeks of
  backups before rotating them. Note: depending on the size of your library,
  this could use a significant amount of disk space on your web server.
  
  To change the number of days the backups are kept for, edit the file
  `/etc/cron.daily/koha-common` on the web server and change the days parameter
  on this line:
  
  ```
  koha-run-backups --days 2 --output /var/spool/koha
  ```

License
-------
This software is free software licensed under the GPL v3. See the LICENSE
file for details.
