# turbo-goggles
Scripts used for Swinburne Astronomy Online project AST80011, Major Project: Computational Astrophysics

# Usage:
  perl lsstdetect.pl \<opsim output.db\> \<SWIFT orbit output.csv.gz\> \<params.json\> \<output.csv\>

where:
* \<opsim output.db\> is a candidate opsim run as a SQLite database. See:  http://astro-lsst-01.astro.washington.edu:8082/
* \<SWIFT output.csv.gz\> is an output file from the SWIFT particle simulator
* \<params.json\> is to corresponding params.json file generated from the SWIFT particle simulator
* \<output.csv\> is the output file

