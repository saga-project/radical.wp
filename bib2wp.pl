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
# get args and check syntax
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
  # open input/output files, and alloc vars which survive the parsing loop
  my $in      = new IO::File ($BIB, 'r') || die "Cannot open bib file '$BIB': $!\n";
  my $out     = new IO::File ($WP , 'w') || die "Cannot open bib file '$WP ': $!\n";
  my @lines   = <$in>; # slurp in lines from input file, to be parsed
  my @section = ();    # lines for a single bibtex entry
  my $res     = "";    # resulting WP text
  my $links   = "";    # links to page sections at top
  my $heading = "";    # heading (year) to be printed if there are entries for that year
  my $headed  =  0;    # was heading printed?
  my $biburl  = "https://raw.github.com/saga-project/radical.wp/master/radical_rutgers.bib";


  $in->close ();       # got all lines - can be closed

  chomp (@lines);      # remove newline from all lines

  # main parsing loop
  LINE:
  foreach my $line ( @lines )
  {
    if ( $line =~ /^\s*$/io )
    {
      # skip empty lines
      next LINE;
    }
    elsif ( $line =~ /^##\s+(.+?)\s*$/io )
    {
      # handle bib sections, marked with '^## ...'
      my $title = $1;

      if ( $title eq 'END' )
      {
        # ignore everything after the '^## END' marker line
        last LINE;
      }

      my $lnk = $title;
      $lnk =~ s/\s/_/iog;

      # add the section heading to the result, and add an entry in the top links
      $res   .= sprintf ("\n\n <a name=\"$lnk\"></a><h1><u>$title</u></h1>\n\n");
      $links .= sprintf (" &bull; <a href=\"#$lnk\"><b>$title</b></a> <br>\n");
    }
    elsif ( $line =~ /^#\s+(\d+?)\s*$/io )
    {
      # handle bib year sections, marked with '^## ...'
      # don't print them yet, to avoid empty years - just keep it around so that
      # it can be printed on first valid bib entry
      my $year = $1;
      $heading = "\n <h2><u>$year</u></h2>\n\n";
      $headed  = 0;  # is not yet printed
    }
    elsif ( $line =~ /^#/io )
    {
      # skip other comment lines
      next LINE;
    }
    else
    {
      # all other lines are assumed to belong to a bib entry, and are stored
      # away
      push (@section, $line);

      # if the line is a single '}', then we assume that the bib entry is
      # finished, and we can parse and print it.
      if ( $line =~ /^\s*[^{]*}\s*$/io )
      {
        # concat the lines, and parse the entry
        my $sec      = join ("\n", @section);
        my $iostream = new IO::String ($sec);
        my $parser   = new BibTeX::Parser ($iostream);

        while ( my $e = $parser->next )
        {
          if ( ! $e->parse_ok ) 
          {
            print "Warning: skipping bib entry - parse error\n";
          }
          else
          {
            # successful parsing - grab relevant keys
            my $key    = $e->{'_key'}       || "";
            my $title  = $e->{'title'}      || "";
            my $author = $e->{'author'}     || "";
            my $month  = $e->{'month'}      || "";
            my $year   = $e->{'year'}       || "";
            my $note   = $e->{'note'}       || "";
            my $book   = $e->{'booktitle'}  || $e->{'institution'} || $e->{'journal'} || "";
            my $vol    = $e->{'volume'}     || "";
            my $num    = $e->{'number'}     || "";
            my $type   = $e->{'type'}       || "";
            my $url    = $e->{'published'}  || $e->{'url'} || "";

            # we expect these keys for all valid entries
            unless ( $key    ) { die  "Error  : no key    for entry ?\n";    }
            unless ( $title  ) { warn "Warning: no title  for entry $key\n"; }
            unless ( $author ) { warn "Warning: no author for entry $key\n"; }
            unless ( $year   ) { warn "Warning: no year   for entry $key\n"; }

            # append journal details to 'book'
            $book  .= ", vol. $vol" if $vol;
            $book  .= " # $num"     if $num;
            $book  .= ", $type"     if $type;
            $book  .= ","           if $book;

            # grab pdf links
            $url    =~ s/^.*{(.*?\.pdf)}.*$/$1/i;
            $url    = " [<a title=\"pdf\" href=\"$url\">pdf</a>] " if $url;

            # replace 'and's in author list
            $author =~ s/ and /, /g;
            $year   =~ s/\D//g;

            # remove brackets from strings
            $title  =~ tr/{}//ds; 
            $author =~ tr/{}//ds; 
            $month  =~ tr/{}//ds; 
            $book   =~ tr/{}//ds; 
            $note   =~ tr/{}//ds; 

            # print year heading if not done so before
            if ( ! $headed )
            {
              $res   .= sprintf ($heading);
              $headed = 1;
            }

            # print entry
            $res .= sprintf ("  <strong> <em> $title </em> </strong>\n");
            $res .= sprintf ("  <em> $author </em>\n");
            $res .= sprintf ("  $book $month $year\n");
            $res .= sprintf ("  $note\n") if ( $note);
            $res .= sprintf ("  $url [<a title=\"bib\" href=\"$biburl\">bib</a>]: $e->{_key}\n");
            $res .= sprintf ("  <br><br>\n");

          } # parse ok
        } # parser->next
        
        # this bib entry is done - clean line list for new entry
        @section = ();
      
      } # end of section
    } # section line
  } # foreach line

  # we got all entries parsed - print top links and all entries to output file
  $out->print ("<hr><br>\n");
  $out->print ($links);
  $out->print ("<hr><br><br>\n");
  $out->print ($res);

  $out->close (); # done, close output.

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

