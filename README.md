# turbo-goggles
Scripts used for Swinburne Astronomy Online project AST80011, Major Project: Computational Astrophysics

# Processing workflow

Steps for simulation run nn 

1. Run simulator providing input parameters: 
    1. Load Solar System, Calculate Cartesian Value, Calculate; Output is planet + test particle positions/velocities after simulation in `ascii.csv.gz` file 
1. Download this file to `runsimnn.csv.gz`; download the parameters file /params.json to `paramsnn.json`
1. Run: `> perl swiftoutputtoinput.pl runsimnn.csv.gz paramsnn.json nn`
1. Run simulator providing TP CSV = `propagatenn.csv` and values Total Integration Time = 11, Integration Timestep = 0.02, Output Timestep = 0.02, output is planet + test particle positions/velocities at approx weekly intervals over 10 years in `ascii.csv.gz` file 
1. Download this file to `runorbitnn.csv.gz`
1. Run: `> perl lsstdetect.pl \<opsim output.db\> \<SWIFT orbit output.csv.gz\> \<params.json\> \<output.csv\>`


# LSSTDetect Usage:
  `> perl lsstdetect.pl \<opsim output.db\> \<SWIFT orbit output.csv.gz\> \<params.json\> \<output.csv\>`

where:
* \<opsim output.db\> is a candidate opsim run as a SQLite database. See:  http://astro-lsst-01.astro.washington.edu:8082/
* \<SWIFT output.csv.gz\> is an output file from the SWIFT particle simulator
* \<params.json\> is to corresponding params.json file generated from the SWIFT particle simulator
* \<output.csv\> is the output file

