
all:
	@rm -f bib/*
	@./bib2wp.pl radical_publications.bib radical_publications.wp radical_publications.redir
	@git add --ignore-removal radical_publications*.wp bib2wp.pl *.bib pdf/ bib/

