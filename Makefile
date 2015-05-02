all: view

memoire.pdf:  memoire.md pdf-template.tex schemas/ancien_schemas.tex
	pandoc -o memoire.pdf --latex-engine xelatex --listings --template pdf-template.tex memoire.md

schemas/ancien_schemas.tex: schemas/ancien_schemas.dia
	dia -e schemas/ancien_schemas.tex schemas/ancien_schemas.dia

view: memoire.pdf
	xdg-open memoire.pdf

clean: memoire.md schemas/ancien_schemas.dia
	rm -f memoire.pdf
	rm -f schemas/ancien_schemas.tex
