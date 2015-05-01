#!
DIR=$( cd -P `dirname "$0"` && pwd )
docker run --rm -it -v $DIR:/source xabufr/pandoc-latex-make-docker make memoire.pdf
