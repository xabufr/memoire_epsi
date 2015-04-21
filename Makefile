all: view

memoire.pdf:  memoire.md pdf-template.tex
	pandoc -o memoire.pdf --latex-engine xelatex --listings --template pdf-template.tex memoire.md

view: memoire.pdf
	xdg-open memoire.pdf

clean: memoire.md
	rm memoire.pdf
