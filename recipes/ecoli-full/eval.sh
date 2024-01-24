#!/bin/sh

###############################################################################
 #
 #  This file is part of verkko-regression, a package that tests the Verkko
 #  whole-genome assembler.
 #
 #  Except as indicated otherwise, this is a 'United States Government Work',
 #  and is released in the public domain.
 #
 #  File 'README.licenses' in the root directory of this distribution
 #  contains full conditions and disclaimers.
 ##

#  To make this script a little bit less specific to each assembly,
#  it needs the name of the assembly as the only argument.

recp=$1

cd $recp

regr=`pwd`              # e.g., /assembly/canu-regression/2020-05-21-1327-master-cafc287f0c6a/drosophila-f1-hifi-24k
recp=`basename $regr`   # e.g., drosophila-f1-hifi-24k
regr=`dirname $regr`    # e.g., /assembly/canu-regression/2020-05-21-1327-master-cafc287f0c6a
regr=`basename $regr`   # e.g., 2020-05-21-1327-master-cafc287f0c6a

if [ -e /data/korens/devel/quast/quast.py ] ; then
  module load minimap2
  module load python/3.7
  export PYTHONPATH=$PYTHONPATH:/data/korens/devel/quast/lib/python3.7/site-packages/
  quast="/data/korens/devel/quast/quast.py"
fi
if [ -e /work/software/bin/quast.py ] ; then
  quast="/work/software/bin/quast.py"
fi

if [ ! -e quast/report.txt ] ; then
  $quast \
    --threads 1 \
    --min-identity 98. \
    --skip-unaligned-mis-contigs \
    --scaffold-gap-max-size 5000000 \
    --min-alignment 10000 \
    --extensive-mis-size 2000 \
    --min-contig 50000 \
    --no-snps \
    -r ../../recipes/$recp/reference.fasta \
    -o quast \
    assembly.fasta \
   > quast.log
  2> quast.err
fi

perl ../../compare.pl -recipe $recp -regression $regr

exit 0
