#!/usr/bin/perl -w

BEGIN {
  use strict;
  use Net::Daemon;
}

################################################################################
#
my $help = <<EOT;

  This service manages on-demand redis service instances.  Instances can be
  created, listed, and killed (canceled).  Creation requires a password.
  Instances are shut down autimatically after some timeout (default: 1 day).  

  Commands:
  ---------

    HELP
          This message.

    CREATE SECRET
           [PASS  = ""          ]
           [TTL   = 60 * 60 * 24]
           [PORT  = <auto>      ]
          Creates a new redis instance on <PORT> with <PASS> and for <TTL> seconds.
          <SECRET> is a password required to create a new redis instance.

    EXTENT id
          Restart ttl counter for server <id>.

    CANCEL id
          Kill server <id>.

    PURGE id 
          Remove state of server <id>.

    PURGE
          Remove state of all finished servers.

    STATUS
          List status for all servers.

    STATUS id
          Show status for server <id>.

    SHUTDOWN SECRET
          Kill this very service.

  Example:
  --------

    telnet 

EOT



################################################################################
#
# the server module
#
package Redishes;

#---------------------------------------------------------------------
# inherits Net::Daemon
our @ISA = "Net::Daemon";

#---------------------------------------------------------------------
# module globals
use Data::Dumper;
use POSIX ":sys_wait_h";


my $SERVER_BIN   = 'redis-server';
my $SERVER_LIMIT = 128;
my $SERVER_TTL   = 60 * 60 * 24;  # one day
my $PORT_MIN     = 10000;
my $PORT_MAX     = $PORT_MIN + $SERVER_LIMIT;
my $ROOT         = "/tmp/redishes/";
my $SECRET       = $ENV{'REDISHES_SECRET'} or die "please set 'REDISHES_SECRET' before running\n";


#---------------------------------------------------------------------
# constructor, just calls base class' c'tor
sub new ($$;$) 
{
  my $type  = shift;
  my $attr  = shift;
  my $args  = shift;

  system ("mkdir -p $ROOT");
  system ("mkdir -p $ROOT/ports/");

  my $self = Net::Daemon->new ($attr, $args);

  bless ($self, $type);

  my $tmp_pid = fork ();
  if ( ! $tmp_pid )
  {
    if ( ! fork () )
    {
      $self->cleaner ();
      exit (0)
    }
    exit (0);
  }

  waitpid ($tmp_pid, 0);

  return $self;
}

sub cleaner ($)
{
  while ( 1 )
  {
    my $active = 0;

    # take care not to purge 'ports/'
    my @server = glob ("$ROOT/*-*/");

    CANCEL:
    foreach my $pwd ( @server )
    {
      next CANCEL if -e "$pwd/canceled";
      next CANCEL if -e "$pwd/timeout";
      next CANCEL if -e "$pwd/done";
      next CANCEL if -e "$pwd/killed";
      next CANCEL if -e "$pwd/timeout";

      my $cancel = 0;

      if    (     -e "$ROOT/action.shutdown" ) { $cancel = 1; }
      elsif (     -e "$pwd/action.cancel"    ) { $cancel = 1; }
      elsif ( not -e "$pwd/ttl"              ) { $cancel = 2; }
      else
      {
        my $ttl   = `cat $pwd/ttl`;  chomp ($ttl);
        my $ctime = ( stat "$pwd/pid" )[10] || next CANCEL;
        my $now   = time;

        if ( $now - $ctime > $ttl )            { $cancel = 2; }
      }


      if ( $cancel )
      {
        my $pid  = undef;
        my $port = undef;

        if ( -e  "$pwd/pid"  ) { $pid  = `cat $pwd/pid`;   chomp ($pid);  }
        if ( -e  "$pwd/port" ) { $port = `cat $pwd/port`;  chomp ($port); }

        # print "pid: $pid $pwd\n";

        if ( defined $pid )
        {
          kill  ( 9, $pid ); # KILL
          kill  (15, $pid ); # TERM
        }
          
        if ( defined $port )
        {
          `rm $ROOT/ports/$port`;
        }

        `rm -f $pwd/action.* >/dev/null 2>&1`;   

        if ( $cancel == 1 )
        {
          print " - canceled $pwd\n";
          `touch $pwd/canceled`;   
        }
        elsif ( $cancel == 2 )
        {
          print " - timeout $pwd\n";
          `touch $pwd/timeout`;   
        }
      }
      else
      {
        $active ++;
      }
    }

    if ( -e "$ROOT/action.shutdown" && $active == 0 )
    {
      `rm -rf $ROOT`;
      print " - shutdown $ROOT\n";
      exit (0);
    }

    if ( -e "$ROOT/action.quit" && $active == 0 )
    {
      `rm -rf $ROOT/action.quit`;
      print " - quit $ROOT\n";
      exit (0);
    }

    sleep (1);
  }
}

#---------------------------------------------------------------------
# overload the Run() method, this is where the action is.  It is invoked for
# each client connection.
sub Run ($) 
{
  my $self   = shift;

  # read from client socket
  my $sock = $self->{'socket'};
  
  $sock->print ("REDIS > "); 
  $sock->flush ();

  while ( defined (my $line = $sock->getline ()) ) 
  {
    my $ret = "";
    my $ttl = $SERVER_TTL;

    chomp $line; # Remove CRLF

    if ( $line =~ /^\s*HELP\s*$/io )
    {
      $ret = $help
    }


    elsif ( $line =~ /^\s*CREATE(?:\s+(\S.*?))?\s*$/io )
    {
      my $opts = $1 || "";
      my $key  = `uuidgen`;
      chomp ($key);

      my @server = glob ("$ROOT/*-*/");

      if ( scalar (@server) >= $SERVER_LIMIT ) {
        $ret = "429 insufficient resources for new redis instance, try again later.\n";
      }

      else {
        $ret = $self->run_server ($key, $opts);
      }
    }


    elsif ( $line =~ /^\s*EXTENT\s+(\S+)\s*$/io )
    {
      my $key = $1;

      if ( ! -d "$ROOT/$key" )
      {
        $ret = "404 redis instance '$key' not found.\n";
      }
      else
      {
        $ret = "200 redis instance '$key' revitalized.\n";
        `touch $ROOT/$key/pid`;
      }
    }


    elsif ( $line =~ /^\s*CANCEL\s+(\S+)\s*$/io )
    {
      my $key = $1;

      if ( ! -d "$ROOT/$key" ) 
      {
        $ret = "404 redis instance '$key' not found.\n";
      }

      else 
      {
        $ret = "202 redis instance '$key' will be canceled.\n";
        `touch $ROOT/$key/action.cancel`;
      }
    }

    
    elsif ( $line =~ /^\s*PURGE\s+(\S+)\s*$/io )
    {
      my $key = $1;
      my $pwd = "$ROOT/$key";

      if ( ! -d $pwd ) 
      {
        $ret = "404 redis instance '$key' not found.\n";
      }

      else 
      {
        if ( -e "$pwd/killed"   or
             -e "$pwd/canceled" or
             -e "$pwd/timeout"  or
             -e "$pwd/done"     )
        {
          `test -e "$pwd/port && rm -f rm $ROOT/ports/\`cat $pwd/port\``;
          `rm -rf $pwd`;
          $ret = "200 redis instance '$key' purged.\n";
        }
        else 
        {
          $ret = "409 redis instance '$key' still running.\n";
        }
      }
    }

    
    elsif ( $line =~ /^\s*PURGE\s*$/io )
    {
      my @pwds = glob ("$ROOT/*-*/");
      for my $pwd ( @pwds )
      {
        if ( -e "$pwd/killed"   or
             -e "$pwd/canceled" or
             -e "$pwd/timeout"  or
             -e "$pwd/done"     )
        {
          `test -e "$pwd/port && rm -f rm $ROOT/ports/\`cat $pwd/port\``;
          `rm -rf $pwd`;
          $ret .= "200 redis instance '$pwd' purged.\n";
        }
      }
    }

    
    elsif ( $line =~ /^\s*STATUS\s*$/io )
    {
      my @keys = `cd $ROOT && ls -d *-*`;
      foreach my $key ( @keys )
      {
        chomp ($key);

        my $status = "unknown";

        if ( -e "$ROOT/$key/running" ) { $status = "running";  }
        if ( -e "$ROOT/$key/killed"  ) { $status = "killed";   }
        if ( -e "$ROOT/$key/done"    ) { $status = "done";     }
        if ( -e "$ROOT/$key/canceled") { $status = "canceled"; }
        if ( -e "$ROOT/$key/timeout" ) { $status = "timeout";  }

        my $pid  = `cat $ROOT/$key/pid`;  chomp ($pid);
        my $ttl  = `cat $ROOT/$key/ttl`;  chomp ($ttl);
        my $port = `cat $ROOT/$key/port`; chomp ($port);
        my $url  = `cat $ROOT/$key/url`;  chomp ($url);

        $ret .= sprintf ("%s : %6s : %6s : %-8s : %s\n", 
                         $key, $pid, $port, $status, $url);
      }
    }


    elsif ( $line =~ /^\s*STATUS\s+(\S+)\s*$/io )
    {
      my $key = $1;

      if ( ! -d "$ROOT/$key" )
      {
        $ret = "404 redis instance '$key' not found.\n";
      }
      else
      {
        my $status = "unknown";

        if ( -e "$ROOT/$key/running" ) { $status = "running";  }
        if ( -e "$ROOT/$key/killed"  ) { $status = "killed";   }
        if ( -e "$ROOT/$key/done"    ) { $status = "done";     }
        if ( -e "$ROOT/$key/canceled") { $status = "canceled"; }
        if ( -e "$ROOT/$key/timeout" ) { $status = "timeout";  }

        my $pid  = `cat $ROOT/$key/pid`;  chomp ($pid);
        my $ttl  = `cat $ROOT/$key/ttl`;  chomp ($ttl);
        my $port = `cat $ROOT/$key/port`; chomp ($port);
        my $url  = `cat $ROOT/$key/url`;  chomp ($url);

        $ret .= sprintf ("%s : %6s : %6s : %-8s : %s\n", 
                         $key, $pid, $port, $status, $url);
      }
    }

    elsif ( $line =~ /^\s*SHUTDOWN\s*$/io )
    {
      `touch $ROOT/action.shutdown`;
      $ret = "202 service will shut down\n";
      $sock->print ("$ret\n");

      print "$ret\n";
      exit  (0);
    }

    elsif ( $line =~ /^\s*QUIT\s*$/io )
    {
      `touch $ROOT/action.quit`;
      $ret = "202 service will quit\n";
      $sock->print ("$ret\n");
      print "$ret\n";
      exit  (0);
    }

    else
    {
      $ret = "418 I'm a teapot.";
    }

    my $log = $ret;
    $log =~ s/^/ > /omg ;

    print " > $line\n";
    print "$log\n";

    my $rc = $sock->print ("$ret\n");
    if ( ! $rc )
    {
      print "error: " . $sock->error () . "\n";
      $self->Error ("Client connection error %s", $sock->error ());
      $sock->close ();
      return;
    }

    $sock->print ("REDIS > "); 
    $sock->flush ();
  }

  if ( $sock->error () ) 
  {
    $self->Error ("Client connection error %s", $sock->error ());
  }

  $sock->flush ();
  $sock->close ();

  # make this service slow...
  sleep (1);
}


sub run_server ($$$)
{
  my $self     = shift;
  my $key      = shift;
  my $opts     = shift;

  my $ttl      = $SERVER_TTL;
  my $port     = -1;
  my $pwd      = "$ROOT/$key";
  my $db       = "$pwd/db";
  my $log      = "$pwd/log";
  my $conf     = "$pwd/conf";
  my $pass     = "";
  my $confpass = "";
  my $secret   = "";

  mkdir ($pwd) or die "Cannot create dir: $!\n";

  # print "opts: $opts\n";
  # print "pwd : $pwd\n";

  if ( $opts  =~ /\bSECRET\s*=\s*(\S+)\b/io ) { $secret = $1; }
  if ( $opts  =~ /\bTTL\s*=\s*(\d+)\b/io )    { $ttl    = $1; }
  if ( $opts  =~ /\bPASS\s*=\s*(\S+)\b/io )   { $pass   = $1; }
  if ( $opts  =~ /\bPORT\s*=\s*(\d+)\b/io )   { $port   = $1; }

  # print "port: $port ($secret - $ttl - $pass)\n";

  if ( ! defined ($secret) or $secret ne $SECRET )
  {
    # starve eventual passwd space scans
    sleep (1);
    return "401 Unauthorized: invalid secret provided";
  }

  if ( $port == -1 ) { $port = $self->find_port ($key); }
  if ( $pass       ) { $confpass = "requirepass $pass"; }


  open (CONF, ">$conf") or die "cannot write config file '$conf': $!\n";
  print CONF <<EOT;
daemonize no
port $port
timeout $ttl
loglevel notice
logfile $log
databases 16
save 900 1
save 300 10
save 60 10000
rdbcompression yes
dbfilename $db
dir $pwd
maxclients 128
appendonly no
appendfsync everysec
vm-enabled no
hash-max-zipmap-entries 64
hash-max-zipmap-value 512
activerehashing yes
$confpass
EOT
  close (CONF);

  `echo $port > $pwd/port`;
  `echo $ttl  > $pwd/ttl`;
  `touch        $pwd/running`;

  # double fork to avoid zombies
  my $tmp_pid = fork ();
  if ( ! $tmp_pid )
  {
    if ( ! fork () )
    {
      my $retval = system ("$SERVER_BIN $conf");

      if ( $retval == -1 ) 
      {
        `echo "failed to execute: $!" >> $pwd/log`;
      }
      elsif ( $retval & 127 )
      {
        my $msg = sprintf ("child died with signal %d", ($retval & 127));
        `echo "$msg" >> $pwd/log`;
        `touch $pwd/killed`;
      }
      else 
      {
        my $exitval = $retval >> 8;
        my $msg = sprintf ("child exited with value %d", $exitval);

        `echo "$msg" >> $pwd/log`;

        if ( $exitval == 0 ) { `touch $pwd/done`  ; }
        if ( $exitval != 0 ) { `touch $pwd/failed`; }
      }

      exit (0);
    }
    exit (0);
  }

  waitpid ($tmp_pid, 0);

  do 
  {
    sleep (1);
  } while ( ! -e $log );

  # store pid for convenience
  my $pid = `ps -e -o pid,cmd| grep $key | grep -v grep | cut -c 1-6`; chomp ($pid);
  `echo $pid  > $pwd/pid`;

  my $url = "";
  my $ret  = "201 creating redis instance '$key': ";
  
  if ( $pass ) 
  { 
    $url = "redis://:XXXXX\@localhost:$port/"; 
    $ret = "redis://:$pass\@localhost:$port/"; 
  }
  else         
  {
    $url = "redis://localhost:$port/"; 
    $ret = "redis://localhost:$port/"; 
  }

  `echo $url  > $pwd/url`;

  return "$key - $ret";
}


sub find_port ($$)
{
  my $self  = shift;
  my $key   = shift;

  foreach my $p ( $PORT_MIN..$PORT_MAX )
  {
    if ( ! -e "$ROOT/ports/$p" )
    {
      `echo $key > $ROOT/ports/$p`;
      return $p;
    }
  }

  # no free port found
  return -1;
}

package main;

Redishes->new ({'pidfile'   => 'none',
                'localport' => 2000,
                'mode'      => 'single'})-> Bind ();

