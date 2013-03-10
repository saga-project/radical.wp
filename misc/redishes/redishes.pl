#!/usr/bin/perl -w

BEGIN {
  use strict;
  use Net::Daemon;
}



######################################################################
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

  if ( ! fork () )
  {
    $self->cleaner ();
  }


  return $self;
}

sub cleaner ($)
{
  while ( 1 )
  {
    my $purged = 0;
    my $active = 0;

    # take care not to purge 'ports/'
    my @server = glob ("$ROOT/*-*/");

    PURGE:
    foreach my $pwd ( @server )
    {
      if ( -e "$pwd/purged" )
      {
        next PURGE;
      }

      my $purge = 0;

      if ( -e "$ROOT/action.shutdown" )
      {
        $purge = 1;
      }
      elsif ( -e "$pwd/action.purge" )
      {
        $purge = 1;
      }
      elsif ( not -e "$pwd/redis.ttl" )
      {
        $purge = 1;
      }
      else
      {
        my $ttl = `cat $pwd/redis.ttl`;  chomp ($ttl);

        my $ctime = ( stat "$pwd/redis.pid" )[10] || next PURGE;
        my $now   = time;

        if ( $now - $ctime > $ttl )
        {
          $purge = 1;
        }
      }

      if ( $purge )
      {
        my $pid  = undef;
        my $port = undef;

        if ( -e  "$pwd/redis.pid"  ) { $pid  = `cat $pwd/redis.pid`;   chomp ($pid);  }
        if ( -e  "$pwd/redis.port" ) { $port = `cat $pwd/redis.port`;  chomp ($port); }

        # print "pid: $pid $pwd\n";

        if ( defined $pid )
        {
          kill  (2, $pid); # INT
          sleep (1);
          kill  (9, $pid); # KILL
        }

        if ( defined $port )
        {
          `rm    $ROOT/ports/$port`;
        }

        `touch $pwd/purged`;
        `rm -f $pwd/action.purge`;

        if ( -e "$ROOT/action.shutdown" )
        {
          `rm -rf $pwd`;
        }

        $purged ++;

        if ( defined $pid )
        {
          print " - purged $pwd : $pid / $port\n";
        }
        else
        {
          print " - purged $pwd / $port\n";
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
  
  while ( defined (my $line = $sock->getline ()) ) 
  {
    my $ret = undef;
    my $ttl = $SERVER_TTL;

    chomp $line; # Remove CRLF

    if ( $line =~ /^\s*REDIS\s+CREATE(?:\s+(\S.*?))?\s*$/io )
    {
      my $opts = $1 || "";
      my $key  = `uuidgen`;
      chomp ($key);

      my @server = glob ("$ROOT/*-*/");

      if ( scalar (@server) >= $SERVER_LIMIT ) {
        $ret = "429 insufficient resources for new redis instance, try again later.";
      }

      else {
        $ret = $self->run_server ($key, $opts);
      }
    }


    elsif ( $line =~ /^\s*REDIS\s+EXTENT\s+(\S+)\s*$/io )
    {
      my $key = $1;

      if ( ! -d "$ROOT/$key" )
      {
        $ret = "404 redis instance '$key' not found.";
      }
      else
      {
        $ret = "200 redis instance '$key' revitalized.";
        `touch $ROOT/$key/redis.pid`;
      }
    }


    elsif ( $line =~ /^\s*REDIS\s+PURGE\s+(\S+)\s*$/io )
    {
      my $key = $1;

      if ( ! -d "$ROOT/$key" ) 
      {
        $ret = "404 redis instance '$key' not found.";
      }

      else 
      {
        $ret = "202 redis instance '$key' will be purged.";
        `touch $ROOT/$key/action.purge`;
      }
    }

    
    elsif ( $line =~ /^\s*REDIS\s+LIST\s*$/io )
    {
      my @server = split (/\s+/, `cd $ROOT && ls -d *-*`);
      foreach my $server ( @server )
      {
        $ret .= " < $server - ";
        $ret .= `cat $ROOT/$server/redis.url`;
      }
    }


    elsif ( $line =~ /^\s*REDIS\s+STATUS\s*$/io )
    {
      my @keys = `cd $ROOT && ls -d *-*`;
      foreach my $key ( @keys )
      {
        chomp ($key);

        my $status = "running";

        if ( -e "$ROOT/$key/purged" ) { $status = "purged"; }

        my $pid  = `cat $ROOT/$key/redis.pid`;  chomp ($pid);
        my $ttl  = `cat $ROOT/$key/redis.ttl`;  chomp ($ttl);
        my $port = `cat $ROOT/$key/redis.port`; chomp ($port);
        my $url  = `cat $ROOT/$key/redis.url`;  chomp ($url);

        $ret .= sprintf (" < %s : %6d : %6d : %-8s : %s\n", 
                         $key, $pid, $port, $status, $url);
      }
    }


    elsif ( $line =~ /^\s*REDIS\s+STATUS\s+(\S+)\s*$/io )
    {
      my $key = $1;

      if ( ! -d "$ROOT/$key" )
      {
        $ret = "404 redis instance '$key' not found.";
      }
      else
      {
        my $pid = `cat $ROOT/$key/redis.pid`;  chomp ($pid);
        print "pid: 'pid'\n";
        $ret = `ls -la $ROOT/$key`;
        $ret = `ps -lf -p $pid`;
        print $ret;
      }
    }

    elsif ( $line =~ /^\s*REDIS\s+SHUTDOWN\s*$/io )
    {
      `touch $ROOT/action.shutdown`;
      $ret = "202 service will shut down";
      print $sock "$ret\n";
      sleep (1);
      exit  (0);
    }

    else
    {
      $ret = "418 I'm a teapot.";
    }

    $ret =~ s/^ <\s*//o ;

    print " > $line\n";
    print " < $ret\n";

    my $rc = print $sock "$ret\n";
    if ( ! $rc )
    {
      print "error: " . $sock->error () . "\n";
      $self->Error ("Client connection error %s", $sock->error ());
      $sock->close ();
      return;
    }
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
  my $db       = "$pwd/redis.db";
  my $log      = "$pwd/redis.log";
  my $conf     = "$pwd/redis.conf";
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
daemonize yes
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
glueoutputbuf yes
hash-max-zipmap-entries 64
hash-max-zipmap-value 512
activerehashing yes
$confpass
EOT
  close (CONF);

  `echo $port > $pwd/redis.port`;
  `echo $ttl  > $pwd/redis.ttl`;

  # new process, start redis server
  system ("$SERVER_BIN $conf");

  do 
  {
    sleep (1);
  } while ( ! -e $log );

  # store pid for convenience
  my $pid = `ps -e -o pid,cmd| grep $key | grep -v grep | cut -c 1-6`; chomp ($pid);
  `echo $pid  > $pwd/redis.pid`;

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

  `echo $url  > $pwd/redis.url`;

  return $ret;
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

