#!/usr/bin/perl -w

################################################################################
#
# this script migrates svn repositories to git.  Branches migrated as git
# branches, tags are converted to git tags.  Logs are fully migrated (under the
# assumption that there were no commits onto tags).
#
# The script accepts a single parameter, which is a control file.  See
# svn2git.example.ctrl for a documented example file.
#
################################################################################

BEGIN {
  use strict;
}

my $giturl   = "";
my $tmp      = "";
my $svntmp   = "";
my $gittmp   = "";
my $svnurl   = "";
my $svnuser  = "";
my $svnpass  = "";
my @trunks   = ();
my @tags     = ();
my @branches = ();
my @ctrl     = ();


# get unbuffered I/O
$| = 1;

# read control file
{
  my $CTRL = shift || die "\n\tusage: $0 <control>\n\n";

  open    (IN, "<$CTRL") || die "Cannot open control file $CTRL\n";
  @ctrl = <IN>;
  close   (IN);
}

# parse control file
{
  foreach my $line ( @ctrl )
  {
    # weed out comments
    $line =~ s/ *#.*$//g;

    if ( $line =~ /\S/o )
    {
      my ($key, $val) = split (/ *: */, $line, 2);

      chomp ($key);
      chomp ($val);

         if ( $key eq 'giturl'   ) { $giturl  = $val; }
      elsif ( $key eq 'tmp'      ) { $tmp     = $val; }
      elsif ( $key eq 'svnurl'   ) { $svnurl  = $val; }
      elsif ( $key eq 'svnuser'  ) { $svnuser = $val; }
      elsif ( $key eq 'svnpass'  ) { $svnpass = $val; }
      elsif ( $key eq 'trunk'    ) { push (@trunks,   $val); }
      elsif ( $key eq 'tags'     ) { push (@tags,     $val); }
      elsif ( $key eq 'branches' ) { push (@branches, $val); }
      else                         { die "cannot parse line '$line'\n"; }
    }
  }
}

# strip trailing slashes
{
  $giturl =~ s/\/$//g;
  $tmp    =~ s/\/$//g;
  $svnurl =~ s/\/$//g;
}

# some fallbacks and checks
{
  unless ( $tmp    ) { $tmp = "/tmp/svn-git"; }
  unless ( $giturl ) { die "no target git repository specified\n"; }
}

# create the tmp dirs
{
  $svntmp = "$tmp/svn";
  $gittmp = "$tmp/git";

  print "prepare temp storage\n";
  print qx{ mkdir -p $tmp    };
  print qx{ mkdir -p $svntmp };
  print qx{ mkdir -p $gittmp };
}


# make a local copy of the remote svn
{
  print "mirror svn to local\n";
  print qx{ svnadmin create        $svntmp};
  print qx{ echo     '#!/bin/sh' > $svntmp/hooks/pre-revprop-change };
  print qx{ chmod    0755          $svntmp/hooks/pre-revprop-change };
  print qx{ svnsync  init   file://$svntmp $svnurl --username $svnuser --password $svnpass };
  print qx{ svnsync  sync   file://$svntmp         --non-interactive };
}

# init local git with mirrored svn
{
  chdir ("$tmp/git/") || die "cannot find tmp dir ($tmp): $!\n";

  my $cmd = "git svn init --prefix=svn/ file://localhost$svntmp/";

  foreach my $trunk  ( @trunks   ) { $cmd .= " -T $trunk" ; }
  foreach my $tag    ( @tags     ) { $cmd .= " -t $tag"   ; }
  foreach my $branch ( @branches ) { $cmd .= " -b $branch"; }

  if ( $svnuser ) { $cmd .= " --username $svnuser"; }

  print "  $cmd\n";
  print qx{$cmd};
}


# fix git config (remove double slashes from paths)
{
  my $cmd = "sed -i -e 's|\\([^:]\\)//|\\1/|g' .git/config";

  print "  $cmd\n";
  print qx{$cmd};
}


# fetch content from svn
{
  my $cmd = "git svn fetch";

  print "  $cmd\n";
  print qx{$cmd};
}


# get all imported branches, and pull them to local.  Then get all branches
# which were fetched from svn tags, and convert them to git tags.
my @rem_branches = ();
my @loc_branches = ();
my @tag_branches = ();
{
  @rem_branches = split (/\s+/s, qx{git branch -a | grep -e '^ *remotes/svn/'});
  @rem_branches = grep  (/\S/, @rem_branches);

  foreach my $rem_branch ( @rem_branches )
  {
    my $loc_branch = $rem_branch;
       $loc_branch =~ s/^remotes\/svn\///g;

    push (@loc_branches, $loc_branch);

    # convert remote branch into local one
    my $cmd = "git branch   $loc_branch \t $rem_branch";
    print "  $cmd\n";
    print qx{$cmd};

    $cmd = "git checkout $loc_branch";
    print "  $cmd\n";
    print qx{$cmd};

    $cmd = "git checkout master";
    print "  $cmd\n";
    print qx{$cmd};

    foreach my $svntag ( @tags )
    {
      if ( $loc_branch =~ /^$svntag(.+)/ )
      {
        my $tag = $1;

        # convert tag branch into tag
        my $cmd = "git tag $tag $loc_branch";
        print "  $cmd\n";
        print qx{$cmd};
           
        # remove old local branch : (first co the tag to do so)
        $cmd = "git checkout $tag";
        print "  $cmd\n";
        print qx{$cmd};

        $cmd = "git branch -d $loc_branch";
        print "  $cmd\n";
        print qx{$cmd};
      }
    }

    # # remove old remote branch
    # $cmd = "git branch -d -r svn/$loc_branch";
    # print "  $cmd\n";
    # print qx{$cmd};
  }
}

# push to git
{
  my $cmd = "git remote add origin $giturl";
  print "  $cmd\n";
  print qx{$cmd};

  $cmd = "git push --all origin";
  print "  $cmd\n";
  print qx{$cmd};

  $cmd = "git push --tags origin";
  print "  $cmd\n";
  print qx{$cmd};
}

# ...
# profit

