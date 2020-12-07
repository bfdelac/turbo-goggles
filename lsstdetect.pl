  use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
  use DBI;
  use Data::Dumper qw(Dumper);
  use Math::Trig;
  use Math::Trig ':radial';
  use POSIX;
  use JSON;

  print "LSST Simulated Detection of SWIFT test particles\n";

sub trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

sub getProposalDetection {
  $dbh = $_[0];
  $ptnum = $_[1];
  $prop = $_[2];
  $query = "select count(*) as nightdetections, night from tpfieldhit where ptnum = $ptnum and $prop and apparentMag <= fiveSigmaDepth group by night order by night;";

  $pdh = $dbh->prepare($query);
  $pdr = $pdh->execute();

  $nightm1 = -1;
  $nightm2 = -1;

  while(my @detectiondate = $pdh->fetchrow_array()) {
    $night = $detectiondate[1];

    if (($nightm2 > 0) && (($night - $nightm2) <= 15)) {
      return 1;
    }

    $nightm2 = $nightm1;
    $nightm1 = $night;    
  }

  return 0;
}

sub summarisepoint {
  $dbh = $_[0];
  $ptnum = $_[1];
  $absmag = $_[2];
  $sma = $_[3];
  $inc = $_[4];
  $ecc = $_[5];

  # 1. for each point, was it discovered? 2 detections per night, with 3 nights within 15 nights, with WFD, with NES, with both?
  # 2. what is the average detection magnitude difference - with WFD, with NES, with both?
  # 3. how many times was it in a field - with WFD, with NES, with both?
  # 4. how many times was it imaged - with WFD, with NES, with both?

  # 1.
  $query = "select count(*) as numhits, COALESCE(avg(apparentMag - fiveSigmaDepth), 0) as avgMagExcess, COALESCE(sum( CASE WHEN apparentMag <= fiveSigmaDepth THEN 1 ELSE 0 END ), 0) as numimgs from tpfieldhit where ptnum = $ptnum and isWFD = 1;";
  
  $smh = $dbh->prepare($query);
  $smr = $smh->execute();

  if(my @ptsummary = $smh->fetchrow_array()) {
    $numhitsWFD = $ptsummary[0];
    $avgMagExcessWFD = $ptsummary[1];
    $numimgsWFD = $ptsummary[2]
  }
  $detectedWFD = getProposalDetection($dbh, $ptnum, "isWFD <> 0");

  $query = "select count(*) as numhits, COALESCE(avg(apparentMag - fiveSigmaDepth), 0) as avgMagExcess, COALESCE(sum( CASE WHEN apparentMag <= fiveSigmaDepth THEN 1 ELSE 0 END ), 0) as numimgs from tpfieldhit where ptnum = $ptnum and isNES = 1;";

  $smh = $dbh->prepare($query);
  $smr = $smh->execute();

  if(my @ptsummary = $smh->fetchrow_array()) {
    $numhitsNES = $ptsummary[0];
    $avgMagExcessNES = $ptsummary[1];
    $numimgsNES = $ptsummary[2];
  }
  $detectedNES = getProposalDetection($dbh, $ptnum, "isNES <> 0");

  $query = "select count(*) as numhits, COALESCE(avg(apparentMag - fiveSigmaDepth), 0) as avgMagExcess, COALESCE(sum( CASE WHEN apparentMag <= fiveSigmaDepth THEN 1 ELSE 0 END ), 0) as numimgs from tpfieldhit where ptnum = $ptnum and isOther = 1;";

  $smh = $dbh->prepare($query);
  $smr = $smh->execute();

  if(my @ptsummary = $smh->fetchrow_array()) {
    $numhitsother = $ptsummary[0];
    $avgMagExcessother = $ptsummary[1];
    $numimgsother = $ptsummary[2];
  }
  $detectedother = getProposalDetection($dbh, $ptnum, "isOther <> 0");

  $query = "select count(*) as numhits, COALESCE(avg(apparentMag - fiveSigmaDepth), 0) as avgMagExcess, COALESCE(sum( CASE WHEN apparentMag <= fiveSigmaDepth THEN 1 ELSE 0 END ), 0) as numimgs from tpfieldhit where ptnum = $ptnum and ((isWFD = 1) or (isNES = 1));";

  $smh = $dbh->prepare($query);
  $smr = $smh->execute();

  if(my @ptsummary = $smh->fetchrow_array()) {
    $numhitscomb = $ptsummary[0];
    $avgMagExcesscomb = $ptsummary[1];
    $numimgscomb = $ptsummary[2];
  }
  $detectedcomb = getProposalDetection($dbh, $ptnum, "((isWFD <> 0) || (isNES <> 0))");

  print $TPH "$ptnum, $absmag, $sma, $inc, $ecc, $numhitsWFD, $numimgsWFD, $avgMagExcessWFD, $detectedWFD, $numhitsNES, $numimgsNES, $avgMagExcessNES, $detectedNES, $numhitscomb, $numimgscomb, $avgMagExcesscomb, $detectedcomb, $numhitsother, $numimgsother, $avgMagExcessother, $detectedother\n";
  print "$ptnum: imaged $numimgscomb out of $numhitscomb, " . ($detectedcomb > 0 ? "detected" : "not detected") . "\n";
}

sub findhits {
  $dbh = $_[0];
  $ptnum = $_[1];
  $timeperiod = $_[2];
  $timeperioddur = $_[3];
  $fieldid = $_[4];
  $dist = $_[5];
  $absmag = $_[13];

  # convert timeperiod to night number.
  $nightstart = floor(($timeperiod * $timeperioddur) * 365.2422);
  $nightend = floor((($timeperiod + 1) * $timeperioddur) * 365.2422);

  $ra = $_[14];
  $dec = $_[15];

  $query = "select distinct * from ObsHistory where Night >= $nightstart and Night < $nightend and Field_fieldId = $fieldid order by night, observationStartTime";
  # print " checking obshistory: " . $query . "\n";

  $obh = $dbh->prepare($query);
  $obr = $obh->execute();

  $night = -1;

  # at 30 au, we add 14.8 to the abs magnitude; at 200 au we add 23 to the abs magnitude

  $appmag = $absmag + 10 * (log($dist)/log(10));
  # print " Calculating appmag = $absmag + 10 * log10($dist) = $appmag\n";
  # this looks like it needs to be scaled

  # print " hits with $query\n";
  while(my @obsr = $obh->fetchrow_array()) {
    # print "  HIT pt $ptnum for timeperiod $timeperiod, field $fieldid: night = $obsr[2] time $obsr[3], filter: $obsr[9], app mag = " . sprintf("%.3f", $appmag) . ", - 5s mag = " . sprintf("%.3f", $obsr[24]) . "\n";

    $query = "select * from ObsProposalHistory where ObsHistory_observationId = $obsr[0];";

    # Proposal 1 - name = NorthEclipticSpur, type = General
    # Proposal 2 - name = SouthCelestialPole, type = General
    # Proposal 3 - name = WideFastDeep, type = General
    # Proposal 4 - name = GalacticPlane, type = General
    # Proposal 5 - name = DeepDrillingCosmology1, type = Sequence
    # print "preparing $query\n";

    $oph = $dbh->prepare($query);
    $opr = $oph->execute();
    $hasNES = 0;
    $hasWFD = 0;
    $hasOther = 0;
    # print "about to enter while\n";
    while(my @proposal = $oph->fetchrow_array()) {
      if ($proposal[2] == $propWFD) {
        $hasWFD = 1;
      } elsif ($proposal[2] == $propNES) {
        $hasNES = 1;
      } else {
        $hasOther = 1;
      }

      # print "   ... on Proposal $proposal[2]\n";
    }
#  $query = "CREATE TEMP TABLE tpfieldhit (ptnum INTEGER, night INTEGER, obsStartTime REAL, fieldid INTEGER, dist REAL, absMag REAL, apparentMag REAL, fiveSigmaDepth REAL, isWFD BOOL, isNES BOOLEAN);";
#          $query = "insert into pointfieldhit (ptnum, timeperiod, fieldid, dist) values ($_[1], $tpposr[1], $fieldr[0], $rho);
#    $absmag = 6;
    $query = "insert into tpfieldhit (ptnum, night, obsStartTime, fieldid, dist, absMag, apparentMag, filter, fiveSigmaDepth, isWFD, isNES, isOther, tpELat, lpELon, fieldELat, fieldELon, angDistFromFieldCentre) values " .
               " ( $ptnum, $obsr[2], $obsr[3], $fieldid, $dist, $absmag, $appmag, '" . $obsr[9] . "', $obsr[24], $hasWFD, $hasNES, $hasOther, $_[8], $_[9], $_[10], $_[11], $_[12]);";
    # print " query = " . $query . "\n";
    $tpfh = $dbh->prepare($query);
    $tpfr = $tpfh->execute();

  }
}

sub processpoint {
  $dbh = $_[0];
  $query = "select * from tppos where ptnum = " . $_[1] . " order by timeperiod;";
  #print $query . "\n";
  $pth = $dbh->prepare($query);
  $ptr = $pth->execute();

  # assign an absolute magnitude
  # based loosely on https://arxiv.org/pdf/1401.2157.pdf but much less pronounced in order to provide a representative sample at each magnitude
  # range 5 <= absolute magnitude <= 15

  # take a random number 1..1024
  # log2() is in range 0..10, we will shift this to be in the range 0..10.

  $absmag = 1.0 * log(1 + rand(1023))/log(2);

  $closestcentre = -1;
  while(my @tpposr = $pth->fetchrow_array()) {
    if ($tpposr[1] <= 1000000) {
      ($rho, $longr, $phi) = cartesian_to_spherical($tpposr[2], $tpposr[3], $tpposr[4]);
#      $latr = 90 - $phi;
      $longd = rad2deg($longr);
      $latd = 90 - rad2deg($phi);
      if ($tpposr[1] == 0 ) {
        print "pt $_[1] time $tpposr[1]: x = " . sprintf("%.3f", $tpposr[2]) . ", y = " . sprintf("%.3f", $tpposr[3]) . ", z = " . sprintf("%.3f", $tpposr[4]) . ", dist = " . sprintf("%.3f", $rho) . ", lat = " . sprintf("%.3f", $latd) . ", long = " . sprintf("%.3f", $longd) . ", absmag = " . sprintf("%.3f", $absmag) . "\n";
      }

      $fieldradius = 1.75;
      $fieldradiuswithbuffer = 2;
      $fieldradiussq = (9.33 / 4.0); # div by 4 to convert from diameter to radius

      $query = "select * from Field where (el > ($longd - $fieldradiuswithbuffer) and el < ($longd + $fieldradiuswithbuffer)) and (eb > ($latd - $fieldradiuswithbuffer) and eb < ($latd + $fieldradiuswithbuffer));";
      # need to allow for wrapping around near 180deg long? although check to see whether this is a factor

      if ($longd > (180 - $fieldradiuswithbuffer)) {
        $query = "select * from Field where (el > ($longd - $fieldradiuswithbuffer) or (el + 360) < ($longd + $fieldradiuswithbuffer)) and (eb > ($latd - $fieldradiuswithbuffer) and eb < ($latd + $fieldradiuswithbuffer));";
      } elsif ($longd < (-180 + $fieldradiuswithbuffer)) {
        $query = "select * from Field where ((el - 360) > ($longd - $fieldradiuswithbuffer) or el < ($longd + $fieldradiuswithbuffer)) and (eb > ($latd - $fieldradiuswithbuffer) and eb < ($latd + $fieldradiuswithbuffer));";
      }

      $llh = $dbh->prepare($query);
      $llr = $llh->execute();
      while(my @fieldr = $llh->fetchrow_array()) {
        $degfromfieldcentresq = ($fieldr[7] - $longd)**2 + ($fieldr[8] - $latd)**2;
        #if($degfromfieldcentresq < $fieldradiussq) {
        #  print "      IN ";
        #} else {
        #  print "         ";
        #}
        #print "field id = $fieldr[0], elat = $fieldr[8], elong = $fieldr[7]; dist = " . sqrt($degfromfieldcentresq) . "\n";

        if(!exists($updatedfields{$fieldr[0]})) {
          $query = "select count(*) as numminusone from ObsHistory where Field_fieldId <= 0 and ra > ($fieldr[3] - 0.01) and ra < ($fieldr[3] + 0.01) and dec > ($fieldr[4] - 0.01) and dec < ($fieldr[4] + 0.01);";
          $uohh = $dbh->prepare($query);
          $uohr = $uohh->execute();
          #print "  checking count with $query\n";
          while(my @numminusone = $uohh->fetchrow_array()) {
            if ($numminusone[0] > 0) {
              $query = "update ObsHistory set Field_fieldId = $fieldr[0] where ra > ($fieldr[3] - 0.01) and ra < ($fieldr[3] + 0.01) and dec > ($fieldr[4] - 0.01) and dec < ($fieldr[4] + 0.01);";
              print " running update query: $query\n";
              $uohh = $dbh->prepare($query);
              $uohr = $uohh->execute();
            }
          }
          $updatedfields{$fieldr[0]} = 1;
        }

        if ($degfromfieldcentresq < $fieldradiussq) {           
          findhits($dbh, $_[1], $tpposr[1], $_[2], $fieldr[0], $rho, $latd, $longd, $fieldr[8], $fieldr[7], $latd, $longd, sqrt($degfromfieldcentresq), $absmag, $fieldr[3], $fieldr[4]);
        }
      }

    }
#    print $_[1] . " point's timeperiod = " . $tpposr[1] . "\n";
#    $timestep++;
  }

  # now that we have which fields the TP will be within, via magnitude, for each time step
  #for each pointfieldhit {
  #  select * from observation where night < 
  #}
  
}

  $stime = time();
  $argvsize = @ARGV;
  if ($argvsize == 0) {
    print "usage: perl $0 <opsim output.db> <SWIFT orbit output.csv.gz> <params.json> <output.csv>\n";
    print "download opsim runs from: http://astro-lsst-01.astro.washington.edu:8080\n";

    print "From a completed orbit simulation, download ascii.csv.gz as <simulationorbitnn.csv.gz> to hard drive\n";
    print "perl version: " . $] . "\n";
    exit(0);    
  }

  if ($argvsize < 4) {
    print "Insufficient arguments\n";
    exit(0);
  }

  print $ARGV[1] . "\n";

  srand(82);

#  $i = 0;
#  while ($i < 1000) {
#    $ri = 1 + rand(1023);
#    $rl = log($ri)/log(2);
#    print "rand $i = $rl\n";
#    $i++;
#  }

  $dbh = DBI->connect("DBI:SQLite:dbname=$ARGV[0]", "", "", {sqlite_open_flags => SQLITE_OPEN_READONLY,})
    or die $DBI::errstr;

  $query = "CREATE TEMP TABLE tppos (ptnum INTEGER, timeperiod INTEGER, x REAL, y REAL, z REAL, vx REAL, vy REAL, vz REAL, a REAL, e REAL, inc REAL);";
  $sth = $dbh->prepare($query);
  $rv = $sth->execute();

  $query = "CREATE TEMP TABLE tpfieldhit (ptnum INTEGER, night INTEGER, obsStartTime REAL, fieldid INTEGER, dist REAL, absMag REAL, apparentMag REAL, filter TEXT, fiveSigmaDepth REAL, isWFD BOOL, isNES BOOLEAN, tpELat REAL, lpELon REAL, fieldELat REAL, fieldELon REAL, angDistFromFieldCentre REAL, isOther BOOLEAN);";
  $pfh = $dbh->prepare($query);
  $pfe = $pfh->execute();

  print "uncompressing " . $ARGV[1] . "...\n";
  $z = new IO::Uncompress::Gunzip $ARGV[1]
    or die "gunzip failed\n";

  print "reading orbit params from " . $ARGV[2] . "...\n";
  open $jh, "<", $ARGV[2];
  $json = <$jh>;
  close $jh;
  $particledata = decode_json($json);

  open($TPH, '>', $ARGV[3]);

  $i = 0;
  #my %tps;

  $timeelapsed = 0;
  $timeperiod = -1;
  $lasttimeyr = -1;

  $ptlimittest = 25000000;
  
  print "analysing...\n";

  $stime = time();

  # sleep 3;

  # $etime = time();

  # $startingdt = localtime();
  # $timediff = $etime - $stime;
  # print "timediff = $timediff, end time = " . localtime($etime) . "\n";
  
  print $TPH "particle, absmag, sma, inc, ecc, field hit (WFD), times imaged (WFD), avg mag excess (WFD), detected (WFD), field hit (NES), times imaged (NES), avg mag excess (NES), detected (NES), field hit (combined), times imaged (combined), avg mag excess (combined), detected (combined), field hit (other), times imaged (other), avg mag excess (other), detected (other), " . $ARGV[0] . ", " . $ARGV[1] . ", " . $ARGV[2] . ", " . $ARGV[3] . ", " . localtime($stime) . "\n";

  %updatedfields = map { $_ => 1 } $fieldslist;

  $propWFD = -1;
  $propNES = -1;
  $query = "select * from Proposal;";
  $prh = $dbh->prepare($query);
  $prv = $prh->execute();
  while(my @propr = $prh->fetchrow_array()) {
    if($propr[2] eq "WideFastDeep") {
      $propWFD = $propr[0];
    }
    if($propr[2] eq "NorthEclipticSpur") {
      $propNES = $propr[0];
    }
  }
  print "Proposals WFD = $propWFD, NES = $propNES\n";

  while ($line = $z->getline()) {
    @values = split(',', $line);

    if (trim($values[1]) eq "tp" && $values[2] <= $ptlimittest) {  # 
      $timeelapsed = $values[0];
      if($values[0] != $lasttimeyr) {
        $lasttimeyr = $values[0];
        $timeperiod++;
      }
      if (abs($values[3]) > 0.001 || abs($values[4]) > 0.001 || abs($values[5]) > 0.001) {
        $query = "insert into tppos (ptnum, timeperiod, x, y, z, vx, vy, vz, a, e, inc) values ( $values[2], $timeperiod, $values[3], $values[4], $values[5], $values[6], $values[7], $values[8], $values[9], $values[10], $values[11]);";
        if( index($query, "*") < 0) {
	  $sth = $dbh->prepare($query);
          $rv = $sth->execute();
        }
      }
    }
    $i++;
  }

  #print "timeperiod = $timeperiod\n";
  $timeperioddur = $timeelapsed / $timeperiod;
  print "Time periods in $timeelapsed years = $timeperiod -> 1 period = " . $timeperioddur . " years\n";

  $query = "select distinct ptnum from tppos order by ptnum;";
  $sth = $dbh->prepare($query);
  $rv = $sth->execute();

  #print "$ptnum, $absmag, $sma, $inc, $ecc, $numimgsWFD, $avgMagExcessWFD, $detectedWFD, $numimgsNES, $avgMagExcessNES, $detectedNES, $numimgcomb, $avgMagExcesscomb, $detectedcomb\n";


  while(my @point = $sth->fetchrow_array()) {
#    print "Point number: " . $point[0] . "\n";

#    if ($point[0] <= 1) {
      processpoint($dbh, $point[0], $timeperioddur);

      $sma = 0;
      $inc = 0;
      $ecc = 0;

      for my $jparticle ( @{$particledata->{particles}} ) {

#print "particle index = " . $jparticle->{'index'};
        if ($jparticle->{'index'} == ($point[0] - 1)) {
          $sma = $jparticle->{'sma'};
          $ecc = $jparticle->{'ecc'};
          $inc = $jparticle->{'inc'};
#print " sma for particle " . $point[0] . " = $sma, ecc = $ecc, inc = $inc\n";
        }
#print "\n";
      }



      summarisepoint($dbh, $ptnum, $absmag, $sma, $inc, $ecc);
#    }
  }

  $etime = time();

  $enddt = localtime($etime);
  print $TPH "finished:, " . $enddt . ", duration (sec):, " . ($etime - $stime) . "\n";
  close($TPH);


#  $query = "select * from Proposal";
#  $pph = $dbh->prepare($query);
#  $ppv = $pph->execute();
#  while(my @propr = $pph->fetchrow_array()) {
#    print "Proposal $propr[0] - name = $propr[2], type = $propr[3]\n";
#  }

#  print "tp30 = " . $tp[30] . "\n";
#  print "tp30 ts 4.1601 = " . $tp[30]{4.1601} . "\n";

#  print Dumper $tp[30];
#  print $i . "\n";
