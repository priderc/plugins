#!/usr/bin/perl

###########
# FILE: check_ganglia.pl
# THANKS: stratos@bnl.gov for the Ganglia XML sorting code this plugin is based on.
# RESPONSIBLE_PARTY: eli
# SYNOPSIS: check the XML tree from a host gmond or server gmetad port, parse 
#  + for cluster/grid info and get down and dirty with host metrics. Useful both as a 
#  + host check and service check in nagios if targeting a host (less XML to pull that way),
#  + and to dump full cluster statistics in a pretty way.
# LICENSE: GPL, Copyright 2006 Eli Stair <estair {at} ilm {dot} com>
#
# TODO: Add timeout var passed from argv to socket call.
# TODO: call $cluster{host} hash directly instead of seeking within it.
# TODO: Fix some clusters that don't match host checks...
# TODO: add retval matching (range, string, etc)
# TODO: fix warn/crit to measure returned metric 
# TODO: !!! NEXT !!! call $cluster{host} hash directly instead of seeking within it.
# TODO: !!! NEXT !!! better, pass in cluster:host context for direct passing of XML
# TODO: !!! NEXT !!! use syntax localhost:8652 TCP
# TODO: !!! NEXT !!! Pass in path to host XML: /Opteron_2.4_GHz_Dual_Core_16G_Deathstar_Cluster/deathstar1401.lucasfilm.com/bytes_in
# TODO: !!! NEXT !!! Or, since that requires knowing the CLUSTER, make it option and check the hostname as key
# TODO: !!! NEXT !!! for the hash of each cluster found. Still reduces cpu/time drastically
#
###########

# core modules needed:
use IO::Socket;
use XML::Parser;
use Getopt::Long;
use DateTime::Format::Epoch::Unix;

# nagios output compatibility:
use lib "/usr/lib/nagios/plugins";
use utils qw(%ERRORS &print_revision &support &usage);


my $parser = new XML::Parser( Style => "Subs" );

&ProcessArgs;

unless ($socket = IO::Socket::INET->new(Timeout=>10, Proto=>"tcp", PeerAddr=>"$host", PeerPort=>"$port")) { 
    print "UNKNOWN: Can't open socket to host=$host and port=$port: $! \n";
    exit $ERRORS{'UNKNOWN'};
    }


# If provided, send a query string to the gmetad XML query port.
# !!! Note: this requires specifying the /alternate/ port to the standard dump port !!!
if (defined($targetcluster)) {

  # check for defined query options
  if (defined($targethost) && defined($metric)) {
    $querystring = "/$targetcluster/$targethost/$metric\n";
  }elsif (defined($targethost)) {
    $querystring = "/$targetcluster/$targethost\n";
  } else {
    $querystring = "/$targetcluster\n";
  }

  #print "QUERYSTRING = $querystring \n";
  # send formatted query string to the socket
  unless ( $socket->send("$querystring", 0) ) {
    print "Can\'t send to socket on port $port! \n";
    exit $ERRORS{'UNKNOWN'};
  }

}
#$socket="index.html";
unless ($parser->parse($socket)) {
    print "CRITICAL: Can't parse XML stream! ";
    exit $ERRORS{'CRITICAL'};
}

sub isnumeric()
{
    my ($x) = @_;
    if ((0+$x == 0) && (sprintf("%s",sprintf("%d",$x)) ne $x))
      {return 0;}
    else
      {return 1;}
}  

### FUNC: ProcessArgs
sub ProcessArgs {
    GetOptions(
      "H|host=s"	=> \$host, 
      "P|port=i"	=> \$port, 
      "O|output=s"	=> \$output, 
      "T|targethost=s"	=> \$targethost, 
      "C|cluster=s"	=> \$targetcluster, 
      "M|metric=s"	=> \$metric,
      "w|warn=i"	=> \$warn,
      "c|crit=i"	=> \$crit,
    );

    unless (defined $host) {
      print "UNKNOWN: HOST not defined.","\n";
      &cmdusage;
      exit $ERRORS{"UNKNOWN"};
    }

    unless (defined $port) {
      print "UNKNOWN: PORT not defined.","\n";
      &cmdusage;
      exit $ERRORS{"UNKNOWN"};
    }
      
    unless (defined $output) {
      print "UNKNOWN: OUTPUT not defined.","\n";
      &cmdusage;
      exit $ERRORS{"UNKNOWN"};
    }

    if ($output eq "hostcheck") {
      if (defined $targethost) {
        if ($metric) {
          unless (defined $metric) {
            print "UNKNOWN: METRIC not defined.", "\n";
            exit $ERRORS{"UNKNOWN"};
          }
        }
      } else { # targethost wasn't set
        print "UNKNOWN: TARGETHOST not defined.", "\n";
        &cmdusage;
        exit $ERRORS{"UNKNOWN"};
      } #/ unless targethost
    } #/ if hostcheck

    if (defined($warn)) {
      print "WARN defined\n";
      #if ( ! isnumeric($warn) ) { die "NOT NUMERIC \n"; }
      #die "NOT NUMERIC \n" if ( ! isnumeric($warn) ) ;
      die "## $warn is NOT NUMERIC \n" if $_ =~ s/[a-z]//;
    }

    if (defined($crit)) {
      print "CRIT defined\n";
    }

} #/ sub processargs
### /FUNC: ProcessArgs

### /FUNC: cmdusage
sub cmdusage {
    print "\t-H\t hostname/IP: of host to connect to gmetad/gmond on ","\n";
    print "\t-P\t Port: to connect to and retrieve XML ","\n";
    print "\t-O\t Output method: ('cluster' to dump all info | 'hostcheck' to grab for)  ","\n";
    print "\t-T\t Targethost: when 'hostcheck', the host to pull data for ","\n";
    print "\t-M\t Metric: the 'gmetric' defined value to return exclusively ","\n";
    print "\t-w\t warn: int value above which the check will exit in a WARN state","\n";
    print "\t-c\t crit: int value above which the check will exit in a CRITICAL state","\n";

}
### FUNC: cmdusage
    
### FUNC: GRID
sub GRID {
    my ($expat, $element, %attrs) = @_;
    my(%grid);

#@test = keys(%grid);
#print "GRID attrs array = @test ","\n";

    if (%attrs) {
       $grid{NAME}= $attrs{NAME};
    }
# Create Reference ($rclusters) to clusters Array; This is where all clusters are stored.
# At this point the array @clusters is empty and thus $rclusters point to an empty array.
    $rclusters = \@clusters;
}
### /FUNC: GRID


### FUNC: CLUSTER
sub CLUSTER {
    my ($expat, $element, %attrs) = @_;
    my(%cluster);

#@test = keys(%attrs);
#print "CLUSTER attrs array = @test ","\n";
#print "$attrs{LOCALTIME}","\n";

    if (%attrs) {
      $cluster{OWNER} = $attrs{OWNER};
      $cluster{NAME} = $attrs{NAME};
      $cluster{LOCALTIME} = $attrs{LOCALTIME};
    }
    $rcluster = \%cluster;
    my(@hosts);
    $rhosts = \@hosts;
}
### /FUNC: CLUSTER

 
### FUNC: HOST
sub HOST {
    my ($expat, $element, %attrs) = @_;
    my(%host);

#@test = keys(%attrs);
#print "HOST attrs array = @test ","\n";

# add values declared at the cluster level to the host array:
    if (%attrs) {
        $host{NAME} = $attrs{NAME};
        $host{IP}   = $attrs{IP};
        $host{REPORTED}   = $attrs{REPORTED};
    }
# Create a Reference to hash %host.
# The hash %host will run out of scope at the end of the subroutine
# but the reference to %host ($rhost) will still exist. 
    $rhost = \%host; # Reference to Hash host
}
### /FUNC: HOST



### FUNC: HOST_
sub HOST_ {
    push ( @$rhosts,$rhost );
}
### /FUNC: HOST_


### FUNC: METRIC
sub METRIC {
    my ($expat, $element, %attrs) = @_;

#@test = keys(%attrs);
#print "METRIC attrs array = @test ","\n";

    $$rhost{$attrs{NAME}}=$attrs{VAL};
}
### /FUNC: METRIC


### FUNC: CLUSTER_
sub CLUSTER_ {
    $$rcluster{HOSTS}=$rhosts;      

# If reference $rclusters is defined, then we have a GRID Element in the XML
# and thus we are quering an GMETAD Server. We should push the info
# for each cluster in @$rclusters

    if (defined $rclusters) {
        #print "### IN CLUSTER_: push (@$rclusters, $rcluster) \n ";
        push (@$rclusters, $rcluster);
    } elsif ( lc ($output) =~ /cluster/) {
       &cluster_output($rcluster);
    } elsif ( lc ($output) =~ /hostcheck/) {
       #print "*** CLUSTER_ running 'hostcheck' stanza \n";
       &hostcheck_output($rcluster);
    }

}
### /FUNC: CLUSTER_


### FUNC: GRID_
sub GRID_ {
    my ($rcluster);

    foreach $rcluster (@$rclusters) {
       if( lc ($output) =~ /cluster/) {
         #print "***GRID_ running 'cluster_output' stanza ";
         &cluster_output($rcluster);
       } elsif ( lc ($output) =~ /hostcheck/) {
         &hostcheck_output($rcluster);
       }
       #deprecated: testing search of full XML tree in hostcheck function (faster to send query to socket, less XML)
       #} elsif ( lc ($output) =~ /hostsearch/) {
       #  #print "***GRID_ running 'cluster_output' stanza on hostsearch: (\$rcluster = $rcluster\ // \$targetcluster = $targetcluster) \n";
       #  &hostcheck_output($rcluster, $targetcluster);
       #}
    }
    # host was NOT found, exit with an error now:
    #exit $ERRORS{'CRITICAL'}
    print "UNKNOWN: HOST ($targethost) not found in XML! \n";
    exit $ERRORS{'UNKNOWN'}
}
### /FUNC: GRID_


### FUNC: cluster_output
sub cluster_output {
    my($ref) = shift @_;
    my($ref_array)=$$ref{HOSTS};
    my($hostname);
    foreach $i (@$ref_array) {
      $hostname = $i->{NAME};
      print "========== HOSTNAME: $hostname \n";
      while ( my( $key, $value) = each (%$i) ) {
         print "\t$key ==> $value \n";
      }
   }
}
### /FUNC: cluster_output


###: ELI: WTF did I put this in here for??
### DELETEME

### FUNC: output_match
#sub output_match {
#my $output = shift;

# perform string regex match on retval:
#  if ( "$output" =~ /.*$match.*/ ) {
#    print "OK: regex-string ($match) matches login banner.\n";
#    exit 0;
#  } else {
#    print "CRITICAL: regex-string ($match) did not match login banner.\n";
#    exit 2;
#  }

## perform range check for warn/crit values:
#  if ( "$output" >= "$crit" ) {
#    exit 1;
#  } elsif ( "$output" >= "$warn" ) {
#    exit 2;
#  } else {
#    exit 0;
#  }

#} #/sub
### /FUNC: output_match

#^^^^ ##: ELI: WTF did I put this in here for??
#^^^^ ## DELETEME


### FUNC: hostcheck_output
sub hostcheck_output {
    my($ref) = shift @_;
    my($ref_array)=$$ref{HOSTS};
    my($localtime)=$$ref{LOCALTIME};
    my($cluster)=$$ref{NAME};
    my($hostname);

    #print "### In hostcheck_output: TARGETHOST == $targethost \n";

    foreach $hostkey (@$ref_array) {
        $hostname = $hostkey->{NAME};
        #print "### HOSTNAME == $hostname \n";
    	if ("$hostname" eq "$targethost") {

            # populate a new hash with metric elements pulled from the array:
            while (my($key, $value) = each(%$hostkey) ) {
              $host_metrics{$key} = "$value";
            } # /while

            # Calculate times:
            my $checkin = $host_metrics{REPORTED};
            $host_metrics{checkin_long} = (DateTime::Format::Epoch::Unix->parse_datetime( $host_metrics{REPORTED} ));
            $host_metrics{localtime_long} = (DateTime::Format::Epoch::Unix->parse_datetime( $localtime ));
            $host_metrics{host_downtime} = (($localtime - $checkin) / 60 );
            $host_metrics{host_uptime} = (($host_metrics{REPORTED} - $host_metrics{boottime}) / 60 );

            # calculate host_state (UP/DOWN):
            unless ($host_metrics{host_downtime} <= 1) {
              $host_metrics{host_state} = "DOWN";
            } else {
              $host_metrics{host_state} = "UP";
            } #/unless host_state
               

          # Check for running mode, if single metric check skip the pretty phase:
          unless ($metric) {
            # pretty-print a header:
            print "#========= CLUSTER :           $cluster \n";
            print "#========= HOSTNAME:           $hostname \n";
            print "#========= METRIC:             ==>     VALUE: \n";
            foreach $metric (sort keys %host_metrics) {
              printf "%11s%-20s%3s%5s%-80s\n", "", "$metric", "=>", "", "$host_metrics{$metric}";
            } # /foreach
             # formatted output of host state:
             print "#========= Calculated runtime metrics:","\n";
             printf "%11s%-20s%3s%5s%-80s\n", "", "local_time", "=>", "", "$host_metrics{localtime_long}";
             printf "%11s%-20s%3s%5s%-80s\n", "", "host_checkin", "=>", "", "$host_metrics{checkin_long}";
             printf "%11s%-20s%3s%5s%-80.1f\n", "", "host_uptime", "=>", "", "$host_metrics{host_uptime}";
             printf "%11s%-20s%3s%5s%-5s%3s%-15s%-10.1f%-10s\n", "", "host_state", "=>", "", "$host_metrics{host_state}", "", "(checkin_delta:", "$host_metrics{host_downtime}", "minutes)";
             exit $ERRORS{'OK'};
          } else { # unless ($metric)
             if (!defined $host_metrics{$metric}) {
               print "UNKNOWN: ($metric) not found in host XML! ","\n";
               exit $ERRORS{'UNKNOWN'}
             } else {
               print "OK: $metric = $host_metrics{$metric} | $metric=$host_metrics{$metric} \n";
               exit $ERRORS{'OK'};
             }
          } # /unless ($metric)

        } else {# /if ($hostname eq)

        } # /if hostname loop through hash.  We've exhausted input data, exit now:
     } # /foreach $hostkey

# don't exit here, create exit at end of all arrays to be searched (after function exits searching the last hash)
     
} #/sub cluster_output
### /FUNC: hostcheck_output



### END CODE.




### POD Documentation:

=pod

=head1 NAME

check_ganglia.pl --  A Nagios plugin to check host/cluster stats from Ganglia data.

=head1 DESCRIPTION

check_ganglia.pl opens a socket to a GMETAD or GMOND (depending on the Port that you
specify in the command line). It uses XML::Parse to parse the XML input (from GMETAD
or GMOND) and produces Mds or Debug output. 

=head1 SYNOPSIS

WRITEME

=head1 COMMAND LINE OPTIONS

The following command line options are available:

=over 4

=item HOST

Specify the Host you will connect to

=item PORT 

Specify the Port you will connect to

=item OUTPUT

Specify the output format. cluster|hostcheck

=back

=head1 EXAMPLES

Connect to Gmond 

=begin html
<font face="" size=+1 color=red>
WRITEME
</font>

=end html

Connect to gmetad 

=begin html
<font face="" size=+1 color=red>
WRITEME
</font>

=end html

=head1 REQUIRES

IO::Socket;
XML::Parser;
Getopt::Long;
DateTime::Format::Epoch::Unix;

=head1 AUTHOR 

LICENSE: GPL, Copyright 2006 Eli Stair <estair {at} ilm {dot} com>


=pod OSNAMES

=cut

