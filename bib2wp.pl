#!/usr/bin/perl -w

BEGIN {
  use strict;

  use IO::File;
  use IO::String;
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
################################################################################

################################################################################
#
# main
#
{
  my $in      = new IO::File ($BIB, 'r') || die "Cannot open bib file '$BIB': $!\n";
  my $out     = new IO::File ($WP , 'w') || die "Cannot open bib file '$WP ': $!\n";
  my @lines   = <$in>;
  my @section = ();
  my $heading = "";
  my $headed  =  0;  # was heading printed?

  $in->close ();

  chomp (@lines);

  LINE:
  foreach my $line ( @lines )
  {
    if ( $line =~ /^\s*$/io )
    {
      next LINE;
    }
    elsif ( $line =~ /^##\s+(.+?)\s*$/io )
    {
      my $title = $1;

      if ( $title eq 'END' )
      {
        last LINE;
      }

      $out->print ("\n\n<h1><u>$title</u></h1>\n\n");
    }
    elsif ( $line =~ /^#\s+(\d+?)\s*$/io )
    {
      my $year = $1;
      $heading = "\n <h2><u>$year</u></h2>\n\n";
      $headed  = 0;
    }
    elsif ( $line =~ /^#/io )
    {
      next LINE;
    }
    else
    {
      push (@section, $line);

      # end of section?
      if ( $line =~ /^\s*[^{]*}\s*$/io )
      {
        my $sec      = join ("\n", @section);
        my $iostream = new IO::String ($sec);
        my $parser   = new BibTeX::Parser ($iostream);

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
            my $note   = $e->{'note'}       || "";
            my $book   = $e->{'booktitle'}  || $e->{'institution'} || 
                         $e->{'journal'}    || "";
            my $vol    = $e->{'volume'}     || "";
            my $num    = $e->{'number'}     || "";
            my $url    = $e->{'published'}  || $e->{'URL'}         || $e->{'note'} ||
                         $e->{'bdsk-url-1'} || $e->{'eprint'}      || "";

            unless ( $key    ) { die  "Error  : no key    for entry ?\n";    }
            unless ( $title  ) { warn "Warning: no title  for entry $key\n"; }
            unless ( $author ) { warn "Warning: no author for entry $key\n"; }
            unless ( $year   ) { warn "Warning: no year   for entry $key\n"; }

            $book  .= ", vol. $vol" if $vol;
            $book  .= " # $num"   if $num;
            $book  .= ","         if $book;

            $url    =~ s/^.*{(.*?\.pdf)}.*$/$1/i;
            $url    = " [<a title=\"pdf\" href=\"$url\">pdf</a>] " if $url;

            $author =~ s/ and /, /g;
            $year   =~ s/\D//g;

            $title  =~ tr/{}//ds; 
            $author =~ tr/{}//ds; 
            $month  =~ tr/{}//ds; 
            $book   =~ tr/{}//ds; 
            $note   =~ tr/{}//ds; 

            my $biburl = "https://raw.github.com/saga-project/radical.wp/master/radical_rutgers.bib";

            if ( ! $headed )
            {
              $out->print ($heading);
              $headed = 1;
            }

            $out->print ("  <strong> <em> $title </em> </strong>\n");
            $out->print ("  <em> $author </em>\n");
            $out->print ("  $book $month $year\n");
            $out->print ("  $note\n") if ( $note);
            $out->print ("  $url [<a title=\"bib\" href=\"$biburl\">bib</a>]: $e->{_key}\n");
            $out->print ("  <br><br>\n");

          } # parse ok
        } # parser->next
        
        @section = ();
      
      } # end of section
    } # section line
  } # foreach line
} # main
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

