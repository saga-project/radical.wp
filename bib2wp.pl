#!/usr/bin/perl -w

BEGIN {
  use strict;

  use IO::File;
  use Data::Dumper;
  use BibTeX::Parser;

  sub usage (;$);
}
################################################################################
#
# global vars
#
my $BIB = shift || usage ("Missing 'bib' argument.");
my $WP  = shift || usage ("Missing 'wp'  argument.");
scalar (@ARGV)  && usage ("Too many arguments.");

# define IO streams here to use them in END block
my $in;
my $out;
my $parser;
################################################################################

################################################################################
#
# main
#
{
  $in     = new IO::File ($BIB, 'r') || die "Cannot open bib file '$BIB': $!\n";
  $out    = new IO::File ($WP , 'w') || die "Cannot open bib file '$WP ': $!\n";
  $parser = new BibTeX::Parser ($in);

  my $cnt = 0;

  while ( my $e = $parser->next )
  {
    $cnt++;

    if ( ! $e->parse_ok ) 
    {
      print "Warning: skipping bib e $cnt - parse error\n";
    }
    else
    {
      my $key    = $e->{'_key'}       || "";
      my $title  = $e->{'title'}      || "";
      my $author = $e->{'author'}     || "";
      my $month  = $e->{'month'}      || "";
      my $year   = $e->{'year'}       || "";
      my $book   = $e->{'booktitle'}  || $e->{'institution'} || "";
      my $url    = $e->{'published'}  || $e->{'URL'}         || $e->{'note'} ||
                   $e->{'bdsk-url-1'} || $e->{'eprint'}      || "";

      unless ( $key    ) { die  "Error  : no key    for entry ?\n";    }
      unless ( $title  ) { warn "Warning: no title  for entry $key\n"; }
      unless ( $author ) { warn "Warning: no author for entry $key\n"; }
      unless ( $month  ) { warn "Warning: no month  for entry $key\n"; }
      unless ( $year   ) { warn "Warning: no year   for entry $key\n"; }

      $book  .= ',' if $book;

      $url    =~ s/^.*?([^{"]*\.pdf).*?$/$1/i;
      $url    = " [<a title=\"pdf\" href=\"$url\">pdf</a>] " if $url;

      $author =~ s/ and /, /g;
      $year   =~ s/\D//g;

      $title  =~ tr/{}//ds; 
      $author =~ tr/{}//ds; 
      $month  =~ tr/{}//ds; 
      $book   =~ tr/{}//ds; 

      my $biburl = "http://saga-project.org/saga.bib";

      print $out <<EOT; 
        <strong> <em> $title </em> </strong>
        <em> $author </em>
        $book $month $year
        $url [<a title="bib" href="$biburl">bib</a>]: $e->{_key}

EOT
    }
  }
}
#
################################################################################

################################################################################
#
sub usage (;$)
{
  my $msg = shift || "";
  my $rv  = 0;

  if ( $msg )
  {
    print "\n  Error: $msg\n";
    $rv = -1;
  }
  
  print <<EOT;

  Usage : $0 <bib> <wp>

    bib : input  file in bibtex format
    wp  : output file in wordpress wiki format
  
  This script converts a bibtex file to a list of wordpress-wiki formated
  bibliography entries.  If the bibtex entries contain 'link' information, 
  those are interpreted as URLs linking to the publication itself.  The 
  bibtex file itself is linked at the top of the bibliographie page, and 
  the bib keys are listed at the respective bib entries.

EOT

  exit ($rv);
}
#
################################################################################


END {

  $in ->close ();
  $out->close ();
}

