  use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
  use JSON;

sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

  $argvsize = @ARGV;
  if ($argvsize == 0) {
    print "usage: perl $0 <SWIFT orbit output.csv.gz> <parameters.json> nn\n";
  }

  if ($argvsize < 3) {
    print "Insufficient arguments\n";
  }

  $z = new IO::Uncompress::Gunzip $ARGV[0]
    or die "gunzip failed\n";

  open $jh, "<", $ARGV[1];
  $json = <$jh>;
  close $jh;
  $planetdata = decode_json($json);

  $lasttime = -1;
  @pllines = ();
  @tplines = ();
  $linenum = 1;
  $mass = 1;
  $lowplanetindex = -1;

#  for my $planet ( @{$planetdata->{planets}} ) {
#    print "lpi = $lowplanetindex, index = " . $planet->{'index'} . "\n";
#    if (($lowplanetindex < 0) || ($planet->{'index'} < $lowplanetindex)) {
#      $lowplanetindex = $planet->{'index'};
#    }
#  }
#print "low planet index = $lowplanetindex\n";
#  if (false ) {
  while ($line = $z->getline()) {
    if($linenum > 1) {
      ($yr, $type, $partnum, $xau, $yau, $zau, $vx, $vy, $vz, $sma, $ecc, $incdeg) = split ',', $line;

      $linetime = trim($yr);
      if ($lasttime != $linetime) {
        $lasttime = $linetime;
        @pllines = ();
        @tplines = ();
#print "set time = $lasttime\n";
      }
      
      if (trim($type) eq "pl") {
        if (($lowplanetindex < 0) || ($partnum < $lowplanetindex)) {
          $lowplanetindex = $partnum;
        }
        $mass = 1;
        for my $planet ( @{$planetdata->{planets}} ) {

#print "planet index = " . $planet->{'index'} . "- mass = " . $planet->{'mass'};
          if ($planet->{'index'} == (trim($partnum) - $lowplanetindex)) {
            $mass = $planet->{'mass'};
#print " SETTING MASS for planet " . $planet->{'index'};
          }
#print "\n";
        }
        $plline = $ecc . ", " . $sma . ", " . trim($incdeg) . ", " . $mass . ", " . $xau . ", " . $yau . ", " . $zau . ", " . $vx . ", " . $vy . ", " . $vz . ", 0.001\n";
        push @pllines, $plline;
#print "pushing planet line: $plline";
      } elsif (trim($type) eq "tp") {
        if ((index($ecc, "*") < 0) && (index($sma, "*") < 0) && (index($incdeg, "*") < 0) && (index($xau, "*") < 0) && (index($yau, "*") < 0) && (index($zau, "*") < 0) && (index($vx, "*") < 0) && (index($vy, "*") < 0) && (index($vz, "*") < 0) &&
            ($sma <= 100)) {
          $tpline = $ecc . ", " . $sma . ", " . trim($incdeg) . ", " . $xau . ", " . $yau . ", " . $zau . ", " . $vx . ", " . $vy . ", " . $vz . "\n";
          push @tplines, $tpline;
        }
      }
    }

    $linenum++;
  }

  open(PLH, '>', 'planet' . $ARGV[2] . '.csv');
  foreach (@pllines) {
    print PLH $_;
  }
  close(PLH);
  open(TPH, '>', 'testparticle' . $ARGV[2] . '.csv');
  foreach (@tplines) {
    print TPH $_;
  }
  close(TPH);

  print "output to input completed\n";
