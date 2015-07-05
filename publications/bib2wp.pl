#!/usr/bin/perl -w

BEGIN 
{
  use strict;

  use IO::File;       # for input and output files
  use IO::String;     # for bibtex parser
  use Data::Dumper;   # for debugging
  use BibTeX::Parser; # for bibtex parsing

  sub pdf2draft ($);
  sub usage     (;$);     
}

################################################################################
#
# globals, args and syntax check
#
my $BIB = shift || usage ("Missing 'bib' argument.");
my $WP  = shift || "$BIB.wp";
my $RED = shift || "$BIB.redir";
# my $WPD = shift || "$WP.drafts";

scalar (@ARGV)  && usage ("Too many arguments.");

my $BIBROOT = "https://www.github.com/saga-project/radical.wp/raw/master/publications";
my $PDFROOT = "$BIBROOT/pdf";
################################################################################

################################################################################
#
# main
#
{
  # open input/output files, and alloc vars which survive the parsing loop
  my $in      = new IO::File ($BIB, 'r') || die "Cannot open bib   file '$BIB': $!\n";
  my $out     = new IO::File ($WP , 'w') || die "Cannot open wp    file '$WP ': $!\n";
  my $redir   = new IO::File ($RED, 'w') || die "Cannot open redir file '$RED': $!\n";
# my $outd    = new IO::File ($WPD, 'w') || die "Cannot open bib file '$WPD': $!\n";

  my @lines   = <$in>; # slurp in lines from input file, to be parsed
  my @section = ();    # lines for a single bibtex entry
  my $txt     = "";    # resulting WP text
# my $txtd    = "";    # resulting WP drafts text
  my $links   = "";    # links to page sections at top
  my $heading = "";    # heading (year) to be printed if there are entries for that year
  my $headed  =  0;    # was heading printed?
  my $biburl  = "$BIBROOT/radical_publications.bib";

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
      $txt   .= sprintf ("\n\n<a name=\"$lnk\"></a><h1><hr/><u>$title</u></h1>\n\n");
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
            $pdfurl = $url;
            $pdfurl =~ s/^.*{(.*?\.pdf)}.*$/$1/i;

            # if pdf does not exist in the 'pdf/' subdir, fetch it.  Only if
            # that succeeds we link the URL...
            if ( $pdfurl && ! -e "pdf/$key.pdf" )
            {
              printf "fetching %-20s \t from $pdfurl ... ", "$key.pdf";
              system ("wget -q -c $pdfurl -O 'pdf/$key.pdf' && echo 'ok' " . 
                      "  || (echo 'fail' && rm pdf/$key.pdf && false)");
            }

            my $pdflnk    = "";
            my $redirtgt  = "";
            if ( -e  "pdf/$key.pdf" )
            {
              pdf2draft ("pdf/$key.pdf");

              if ( -e "pdf/$key\_draft.pdf" )
              {
                $pdflnk    = " [<a title=\"pdf\" href=\"$PDFROOT/$key\_draft.pdf\">pdf</a>] ";
                $redirtgt  = "$PDFROOT/$key\_draft.pdf";
              }
              else
              {
                $pdflnk    = " [<a title=\"pdf\" href=\"$PDFROOT/$key.pdf\">pdf</a>] ";
                $redirtgt  = "$PDFROOT/$key.pdf";
              }
            }


            # if bib does not exist in the 'bib/' subdir, create it.  Only if
            # that succeeds we link the URL...
            if ( ! -e "bib/$key.bib" )
            {
              print "create bib/$key.bib\n";
              open (BIB, ">bib/$key.bib") || die "Cannot create bib file bib/$key.bib: $!\n";
              print BIB "\n################################################################################\n#\n";
              print BIB "$sec";
              print BIB "\n#\n################################################################################\n\n";
              close (BIB);
            }

            my $biblnk = "[<a title=\"bib\" href=\"$BIBROOT/bib/$key.bib\">bib</a>]";


            my $notelnk  = "";
            if ( $note =~ /^(.*?)(?:,\s*)?\\url\{(.+?)\}(?:,\s*)?(.*)$/io )
            {
              my $note_1 = $1 || "";
              my $lnktgt = $2;
              my $note_2 = $3 || "";

              my $comma  = "";
              if ( $note_1 and $note_2 )
              {
                $comma = ", ";
              }

              $note = "$note_1$comma$note_2";
              $notelnk   = "[<a title=\"link\" href=\"$lnktgt\">link</a>]";
              $redirtgt  = $lnktgt;
            }


 
            # replace 'and's in author list
            $author =~ s/ and /, /g;
            $year   =~ s/\D//g;

            # remove brackets and escape '\' from strings
            $title  =~ tr/{}//ds;     $title  =~ tr/\\//ds; 
            $author =~ tr/{}//ds;     $author =~ tr/\\//ds; 
            $month  =~ tr/{}//ds;     $month  =~ tr/\\//ds; 
            $book   =~ tr/{}//ds;     $book   =~ tr/\\//ds; 
            $note   =~ tr/{}//ds;     $note   =~ tr/\\//ds; 

            # print year heading if not done so before
            if ( ! $headed )
            {
              $txt   .= sprintf ($heading);
              $headed = 1;
            }

            if ( $key =~ /^(draft|review)_/io )
            {
              # print entry to drafts
              $txtd .= "  <a name=\"$key\"></a>\n";
              $txtd .= "  <strong> <em> $title </em> </strong>\n";
              $txtd .= "  <em> $author </em>\n";
              $txtd .= "  $book $month $year\n";
              $txtd .= "  $note\n" if ( $note);
              $txtd .= "  $notelnk $pdflnk $biblnk : $key\n";
              $txtd .= "  <br><br>\n";
            }
            else
            {
              # print entry to pubs
              $txt .= "  <a name=\"$key\"></a>\n";
              $txt .= "  <strong> <em> $title </em> </strong>\n";
              $txt .= "  <em> $author </em>\n";
              $txt .= "  $book $month $year\n";
              $txt .= "  $note<br>\n" if ( $note);
              $txt .= "  $notelnk $pdflnk $biblnk : $key\n";
              $txt .= "  <br><br>\n";
            }

            if ( $redirtgt )
            {
                $redir->printf ("http://radical.rutgers.edu/publications/%-35s : %s\n", $key, $redirtgt);
                $redirtgt = ""
            }

          } # parse ok
        } # parser->next
        
        # this bib entry is done - clean line list for new entry
        @section = ();
      
      } # end of section
    } # section line
  } # foreach line

  # add drafts subsection
  $links .= sprintf (" &bull; <a href=\"#drafts\"><b>Drafts / Under Review</b></a> <br>\n");


  # we got all entries parsed - print top links and all entries to output file,
  # and the bibtex link
  $out->print  ("<hr>\n");
  $out->print  ($links);
  $out->printf (" &bull; <a href=\"#bibtex\"><b>BibTeX</b></a>\n");
  $out->print  ($txt);
# $out->print  ("<hr><br><br>\n");
# $out->printf ("\n\n <a name=\"bibtex\"></a><h1><u>BibTeX</u></h1>\n\n");
# $out->printf (" &bull; <a href=\"$BIBROOT/radical_publications.bib\"><b>radical_publications.bib</b></a> <br>\n\n");();
# $out->close  (); # done, close output.

  my $outd = $out;
  $outd->print  ("<hr>\n");
  $outd->print  ("\n<a name=\"drafts\"></a><h1><hr/><u>Drafts / Under Review</u></h1>\n\n");
  $outd->print  ("\n"); 
  $outd->print  ("These publications are work in progress, are under review, or ");
  $outd->print  ("are not yet published for other reasons.  As such, they are ");
  $outd->print  ("likely to change, sometimes significantly, and should not ");
  $outd->print  ("(yet) be referenced directly.  Please contact the repective ");
  $outd->print  ("authors for further details.\n");
  $outd->print  ("\n");
  $outd->print  ($txtd);
  $outd->print  ("<hr><br><br>\n");
  $outd->printf ("\n\n <a name=\"bibtex\"></a><h1><u>BibTeX</u></h1>\n\n");
  $outd->printf (" &bull; <a href=\"$BIBROOT/radical_publications.bib\"><b>radical_publications.bib</b></a> <br>\n\n");();
# $outd->close  (); # done, close output.

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


sub pdf2draft ($)
{
  my $pdf = shift;

  my $tmp  = "/tmp/";
  my $idx  = 0;
  my $pwd  = `pwd`;
  
  chomp ($pwd);

  if ( $pdf =~ /(.*\/)?(.+?)\.pdf$/io )
  {
    my $dir  = $1 || "./";
    my $base = $2;

    if ( $base !~ /_draft$/io &&
         ! -e "$dir/$base\_draft.pdf" )
    {
      $idx++;
      my $id   = "pdf2draft_$$\_$idx";

      print "create $dir/$base\_draft.pdf\n";

      system ("cp $pdf $tmp/$id\_input.pdf");

      open (TMP, ">/$tmp/$id.tex") || die "cannot open tmp file: $!\n";
      print TMP <<EOT;
\\documentclass{article}
\\usepackage{pdfpages}
\\usepackage{graphicx}
\\usepackage{type1cm}
\\usepackage{eso-pic}
\\usepackage{color}
\\makeatletter
\\AddToShipoutPicture{%
            \\setlength{\\\@tempdimb}{.5\\paperwidth}%
            \\setlength{\\\@tempdimc}{.5\\paperheight}%
            \\setlength{\\unitlength}{1pt}%
            \\put(\\strip\@pt\\\@tempdimb,\\strip\@pt\\\@tempdimc){%
        \\makebox(0,0){\\rotatebox{45}{\\textcolor[gray]{0.8}%
        {\\fontsize{5cm}{6cm}\\selectfont{DRAFT}}}}%
            }%
}
\\makeatother
\\begin{document}
\\includepdf[fitpaper=true,pages=1-]{$tmp/$id\_input.pdf}
\\end{document}
EOT
      close (TMP);

      system ("cd $tmp ; pdflatex $id 2>&1 > /dev/null || rm -f $id.pdf");
      system ("cd $pwd ; mv /$tmp/$id.pdf $dir/$base\_draft.pdf");
      system ("rm -f $tmp/$id");
    }
    else
    {
      # print "$pdf is base, or base exists\n";
    }
    
  }

}

