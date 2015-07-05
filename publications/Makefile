
all:
	@rm -f bib/*
	@./bib2wp.pl radical_publications.bib radical_publications.wp radical_publications.redir
	@cat radical_publications.redir | sed -e 's/ *: /,/' > radical_publications.redit.csv
	@git add --ignore-removal radical_publications*.* bib2wp.pl *.bib pdf/ bib/

