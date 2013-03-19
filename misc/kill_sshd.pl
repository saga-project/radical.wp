#!/usr/bin/perl -w

use strict;
use Data::Dumper;

# # redirect stdout and stderr to a log file
# open STDOUT, '>>', "$ENV{HOME}/kill_sshd.log";
# open STDERR, '>>', "$ENV{HOME}/kill_sshd.log";
# 
# printf ("%s: killing idle/orphaned ssh daemons\n", scalar (localtime()));

sub parse_ps_proc ($)
{
  my  $ps_line =  shift;
  if ($ps_line =~ /^\s*(\S+)   # 1: username
                    \s+(\d+)   # 2: pid
                    \s+(\d+)   # 3: ppid
                    \s+(\d)    # 4: c
                    \s+(\S+)   # 5: stime
                    \s+(\S+)   # 6: tty
                    \s+(\S+)   # 7: time
                    \s+(.+?)$  # 8: cmd/iox )
  {
    return { 'line' => $ps_line,
             'user' => $1,
             'pid'  => int($2),
             'ppid' => int($3),
             'cmd'  => $8 };
  }

  return undef;
}

# only kill processes owned by us...
my $USER = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);

# all processes for this users
my @ps_procs   = `ps -ef | grep $USER`;
my @proc_infos = ();

# get rid of newlines
chomp (@ps_procs);

PS_PROC:
for my $ps_proc ( @ps_procs )
{
  my $proc_info = parse_ps_proc ($ps_proc);

  # ignore parse errors:
  push (@proc_infos, $proc_info) unless not defined ($proc_info);
}

# find candidates to clean nup.  Those are all sshd process 
# which don't have a tty anymore, don't have child processes, 
# and have a root owned sshd as parent.
PS_INFO:
for my $proc_info ( @proc_infos )
{
  my $user   = $proc_info->{'user'};
  my $cmd    = $proc_info->{'cmd'};
  my $pid    = $proc_info->{'pid'};
  my $ppid   = $proc_info->{'ppid'};
  my $parent = undef;
  my @kids   = ();


  if ( $cmd !~ /^sshd:\s+$USER\@notty$/io )
  {
    # not an tty-less sshd -- ignore
    next PS_INFO;
  }

  # filter this proc out if not matching our criteria
  for my $tmp ( @proc_infos )
  {
    if ( int($tmp->{'pid'}) == int($ppid) )
    {
      # this is daddy -- check if it is a root owned sshd process
      if ( $tmp->{'cmd'} !~ /^sshd:\s+$USER\s+\[priv\]$/io or
           $tmp->{'user'} ne 'root' )
      {
        # this is not the process you are looking for...
        next PS_INFO;
      }
    }
  }

  # ok, this *is* the process we were looking for -- now get rid of it
  print "killing $proc_info->{'line'} -- ";
  kill (15, $proc_info->{'pid'}) and print "ok\n" or print "failed ($!)\n";
}


